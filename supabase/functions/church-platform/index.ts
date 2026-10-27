import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.110.8";
import { corsHeaders } from "npm:@supabase/supabase-js@2.110.8/cors";

const jsonHeaders = {
  ...corsHeaders,
  "Content-Type": "application/json",
};

const defaultPasswordSetupURL =
  "https://ministryvolunteers.worf.app/reset-password";

type InvitationRole = "admin" | "editor" | "viewer";

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function requiredSecret(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

function serviceKey(): string {
  const single =
    Deno.env.get("SUPABASE_SECRET_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (single) return single;

  const encoded = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!encoded) {
    throw new Error(
      "Missing SUPABASE_SECRET_KEYS or SUPABASE_SERVICE_ROLE_KEY.",
    );
  }
  const keys = JSON.parse(encoded) as Record<string, string>;
  const key = keys.default ?? Object.values(keys)[0];
  if (!key) throw new Error("SUPABASE_SECRET_KEYS has no usable key.");
  return key;
}


Deno.serve(async (request: Request) => {
 if(request.method==='OPTIONS') return new Response(null,{status:204,headers:jsonHeaders});
 if(request.method!=='POST') return json(405,{error:'Method not allowed.'});
 try {
  const token=request.headers.get('Authorization')?.replace(/^Bearer\s+/i,'').trim();
  if(!token) return json(401,{error:'Sign in to continue.'});
  const admin=createClient(requiredSecret('SUPABASE_URL'),serviceKey(),{auth:{autoRefreshToken:false,persistSession:false}});
  const {data:{user},error:authError}=await admin.auth.getUser(token);
  if(authError||!user||!user.email_confirmed_at) return json(401,{error:'A verified email account is required.'});
  const p=await request.json().catch(()=>null);
  if(!p||typeof p.action!=='string') return json(400,{error:'Choose an action.'});
  const {data:profile,error:profileError}=await admin.from('profiles').select('user_id,church_id,app_role,is_platform_admin,access_disabled,must_change_password').eq('user_id',user.id).single();
  if(profileError||!profile||profile.access_disabled||profile.must_change_password) return json(403,{error:'This account cannot perform this action.'});
  if(p.action==='apply') {
   if(profile.church_id||profile.is_platform_admin) return json(409,{error:'Your account already belongs to a church.'});
   const name=typeof p.church_name==='string'?p.church_name.trim():'';
   const location=typeof p.location==='string'?p.location.trim():'';
   if(name.length<2||name.length>160||location.length<2||location.length>240) return json(400,{error:'Enter a church name and location.'});
   const {error}=await admin.from('church_applications').insert({applicant_id:user.id,church_name:name,location});
   if(error?.code==='23505') return json(409,{error:'You already have an application awaiting approval.'});
   if(error) throw error;
   return json(201,{message:'Application received. Your church can join after the developer approves it.'});
  }
  if(p.action==='my_applications') {
   const {data,error}=await admin.from('church_applications').select('id,church_name,location,status,decision_note,created_at').eq('applicant_id',user.id).order('created_at',{ascending:false});
   if(error) throw error;return json(200,{applications:data});
  }
  if(!profile.is_platform_admin||profile.app_role!=='admin') return json(403,{error:'Platform administrator access required.'});
  if(p.action==='overview') {
   const [churches,applications]=await Promise.all([
    admin.from('churches').select('id,name,slug,is_active').order('name'),
    admin.from('church_applications').select('id,applicant_id,church_name,location,status,created_at').eq('status','pending').order('created_at')]);
   if(churches.error||applications.error) throw churches.error??applications.error;

   const pending=applications.data??[];
   const contactApplications=[];
   for(let offset=0;offset<pending.length;offset+=5){
    contactApplications.push(...await Promise.all(pending.slice(offset,offset+5).map(async application=>{
     if(!application.applicant_id)return {...application,applicant_email:null};
     const {data,error}=await admin.auth.admin.getUserById(application.applicant_id);
     if(error)throw error;
     return {...application,applicant_email:data.user.email??null};
    })));
   }
   return json(200,{churches:churches.data,applications:contactApplications});
  }
  if(p.action==='decide') {
   if(typeof p.application_id!=='string'||typeof p.approve!=='boolean'||(p.note!==undefined&&typeof p.note!=='string')) return json(400,{error:'Choose an application and decision.'});
   const {data,error}=await admin.rpc('decide_church_application',{p_actor_id:user.id,p_application_id:p.application_id,p_approve:p.approve,p_note:p.note??''});
   if(error) return json(409,{error:'The decision could not be saved. Refresh the list; the applicant may already belong to a church or the application may already have been decided.'});
   return json(200,{church_id:data,message:p.approve?'Church approved. The applicant is now its first administrator.':'Application declined.'});
  }
  if(p.action==='diagnostics') {
   if(typeof p.church_id!=='string'||!/^[0-9a-f-]{36}$/i.test(p.church_id)||typeof p.reason!=='string'||p.reason.trim().length<10||p.reason.length>1000) return json(400,{error:'Select a church and enter a support reason of at least 10 characters.'});
   const {error:auditError}=await admin.rpc('record_platform_support',{p_actor_id:user.id,p_church_id:p.church_id,p_action:'read_diagnostics',p_reason:p.reason.trim()});
   if(auditError) return json(403,{error:'Support access could not be recorded.'});
   const [church,users,people,assignments,imports]=await Promise.all([
    admin.from('churches').select('id,name,slug,is_active').eq('id',p.church_id).single(),
    admin.from('profiles').select('user_id,display_name,app_role,access_disabled,must_change_password').eq('church_id',p.church_id).order('display_name'),
    admin.from('people').select('id',{count:'exact',head:true}).eq('church_id',p.church_id),
    admin.from('assignments').select('id',{count:'exact',head:true}).eq('church_id',p.church_id),
    admin.from('import_runs').select('id,status,created_at,error_count,conflict_count').eq('church_id',p.church_id).order('created_at',{ascending:false}).limit(10)]);
   for(const result of [church,users,people,assignments,imports]) if(result.error) throw result.error;
   // Select status only: encrypted Planning Center credentials never leave the DB.
   const sync=await admin.rpc('support_sync_status',{p_actor_id:user.id,p_church_id:p.church_id});
   if(sync.error) throw sync.error;

   const supportUsers=[];
   const scopedUsers=users.data??[];
   for(let offset=0;offset<scopedUsers.length;offset+=5){
    supportUsers.push(...await Promise.all(scopedUsers.slice(offset,offset+5).map(async profile=>{
     const {data,error}=await admin.auth.admin.getUserById(profile.user_id);
     if(error) throw error;
     return {...profile,email:data.user.email??null,last_sign_in_at:data.user.last_sign_in_at??null,enrolled:Boolean(data.user.email_confirmed_at)};
    })));
   }
   return json(200,{church:church.data,users:supportUsers,people_count:people.count,assignment_count:assignments.count,imports:imports.data,sync:sync.data});
  }
  return json(400,{error:'Unknown action.'});
 } catch(error) {console.error('Church platform request failed:',error);return json(500,{error:'The request could not be completed. Please try again.'});}
});
