import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {corsHeaders} from "npm:@supabase/supabase-js@2.110.8/cors";
import {adminClient,requireEditor,fetchPerson} from "../_shared/planning-center.ts";
const json=(status:number,value:unknown)=>new Response(JSON.stringify(value),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
async function revision(record:unknown){const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(JSON.stringify(record)));return Array.from(new Uint8Array(digest),v=>v.toString(16).padStart(2,"0")).join("");}
Deno.serve(async(request:Request)=>{
 if(request.method==="OPTIONS")return json(200,{});
 if(request.method!=="POST")return json(405,{error:"Method not allowed."});
 try{
  const caller=await requireEditor(request);
  if(caller.appRole!=="admin")return json(403,{error:"Only administrators can link contacts."});
  const body=await request.json();
  if(!["preview","link","review_duplicate","merge"].includes(body.action)||typeof body.person_id!=="string"||!/^[0-9a-f-]{36}$/i.test(body.person_id)||typeof body.external_id!=="string"||!/^\d{1,20}$/.test(body.external_id))return json(400,{error:"Choose a local contact and a Planning Center profile."});
  const db=adminClient();
  const {data:local,error:localError}=await db.from("people").select("id,first_name,middle_name,last_name,preferred_name,suffix,email,mobile_phone,home_phone,address_line_1,address_line_2,city,state_region,postal_code,country_code,membership_status,is_active,updated_at").eq("church_id",caller.churchId).eq("id",body.person_id).single();
  if(localError||!local)return json(404,{error:"This contact is not in your church."});
  let duplicate=null;
  if(body.action==="review_duplicate"||body.action==="merge"){
   const review=await db.rpc("review_planning_center_duplicate",{p_actor_id:caller.userId,p_person_id:body.person_id,p_external_id:body.external_id});
   if(review.error)return json(409,{error:review.error.message});
   duplicate=review.data;
  }
  const {data:rows,error:credentialsError}=await db.rpc("get_planning_center_credentials",{p_church_id:caller.churchId});
  if(credentialsError||!rows?.[0]?.application_id||!rows?.[0]?.secret)return json(409,{error:"Connect Planning Center before matching contacts."});
  let person;
  try{person=await fetchPerson(body.external_id,{applicationId:rows[0].application_id,secret:rows[0].secret});}catch{return json(502,{error:"Current Planning Center details could not be loaded. Check the connection and try again."});}
  const currentRevision=await revision(person.record);
  if(body.action==="preview"||body.action==="review_duplicate")return json(200,{external_id:person.externalId,record:person.record,revision:currentRevision,local_updated_at:local.updated_at,local_contact:local,duplicate});
  if(body.confirmed!==true||typeof body.revision!=="string"||body.revision!==currentRevision||typeof body.local_updated_at!=="string")return json(409,{error:"Confirm the current comparison before linking or merging. If details changed, review them again."});
  if(body.action==="merge"){
   if(typeof body.merge_revision!=="string"||!body.choices||typeof body.choices!=="object"||Array.isArray(body.choices))return json(400,{error:"Review the duplicate records and overlapping entries before merging."});
   const {data,error}=await db.rpc("merge_planning_center_duplicate",{p_actor_id:caller.userId,p_person_id:body.person_id,p_external_id:person.externalId,p_record:person.record,p_merge_revision:body.merge_revision,p_choices:body.choices});
   if(error)return json(409,{error:error.message});
   return json(200,data);
  }
  const {data,error}=await db.rpc("link_planning_center_contact",{p_actor_id:caller.userId,p_person_id:body.person_id,p_external_id:person.externalId,p_record:person.record,p_expected_updated_at:body.local_updated_at});
  if(error)return json(409,{error:error.message});
  return json(200,data);
 }catch{return json(403,{error:"An active administrator login is required."});}
});
