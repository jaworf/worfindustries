"use client";
import {useEffect,useRef,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
import { SectionHeading } from "./section-heading";
import {type Profile,type Assignment,isCurrent,formatDate} from "./admin-shared";
const bucket="church-logos";
const objectPath=(churchId:string)=>`${churchId.toLowerCase()}/logo`;
function useChurchLogo(client:SupabaseClient,churchId:string,version=0){
 const [url,setUrl]=useState<string|null>(null);
 // eslint-disable-next-line react-hooks/set-state-in-effect -- Remove the previous church logo before fetching a different private storage object.
 useEffect(()=>{let active=true;let objectURL:string|null=null;setUrl(null);void client.storage.from(bucket).download(objectPath(churchId)).then(({data})=>{if(active&&data){objectURL=URL.createObjectURL(data);setUrl(objectURL);}});return()=>{active=false;if(objectURL)URL.revokeObjectURL(objectURL);};},[client,churchId,version]);
 return url;
}
export function ChurchLogoSettings({supabase,profile}:{supabase:SupabaseClient;profile:Profile}){
 const [version,setVersion]=useState(0),[busy,setBusy]=useState(false),[message,setMessage]=useState("");const logo=useChurchLogo(supabase,profile.church_id,version);
 async function upload(file:File){setBusy(true);setMessage("");let temporary:string|null=null;try{
  if(!['image/png','image/jpeg'].includes(file.type)||file.size>2097152)throw Error('Choose a PNG or JPEG smaller than 2 MB.');
  temporary=URL.createObjectURL(file);const image=new Image();image.src=temporary;await image.decode();
  if(!image.width||!image.height)throw Error('This image could not be read. Try another PNG or JPEG.');
  const scale=Math.min(1,1024/Math.max(image.width,image.height));
  const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(image.width*scale));canvas.height=Math.max(1,Math.round(image.height*scale));const context=canvas.getContext('2d');if(!context)throw Error('The image could not be prepared.');context.drawImage(image,0,0,canvas.width,canvas.height);
  let png=await new Promise<Blob>((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(Error('The image could not be prepared.')),'image/png'));
  if(png.size>2097152){canvas.width=Math.max(1,Math.round(canvas.width/2));canvas.height=Math.max(1,Math.round(canvas.height/2));context.drawImage(image,0,0,canvas.width,canvas.height);png=await new Promise<Blob>((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(Error('The image could not be prepared.')),'image/png'));}
  if(png.size>2097152)throw Error('The image could not be prepared. Try exporting it as a smaller PNG or JPEG.');
  const {error}=await supabase.storage.from(bucket).upload(objectPath(profile.church_id),png,{contentType:'image/png',upsert:true,cacheControl:'0'});if(error)throw error;
  setVersion(v=>v+1);setMessage('Your church logo is saved. Reopen Reports to use the updated logo.');
 }catch(e){setMessage(e instanceof Error?e.message:'The logo could not be uploaded.');}finally{if(temporary)URL.revokeObjectURL(temporary);setBusy(false);}}
 return <section className="admin-card admin-settings-card"><h3>Your Church’s Report Logo</h3><p>Upload a PNG or JPEG up to 2 MB. Large images are resized automatically. Your logo appears only on your church’s reports.</p>{logo&&<img src={logo} alt="Your church report logo" style={{maxWidth:180,maxHeight:120,objectFit:'contain'}}/>}<label>Choose church logo<input type="file" accept="image/png,image/jpeg" disabled={busy} onChange={e=>{const file=e.target.files?.[0];if(file)void upload(file);e.target.value='';}}/></label>{logo&&<button className="button" disabled={busy} onClick={async()=>{setBusy(true);const {error}=await supabase.storage.from(bucket).remove([objectPath(profile.church_id)]);setMessage(error?'The logo could not be removed.':'Church logo removed.');if(!error)setVersion(v=>v+1);setBusy(false);}}>Remove Logo</button>}{message&&<p role="status">{message}</p>}</section>;
}
const escapeHTML=(value:string)=>value.replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]!));
export type ReportKind = "directory" | "awaiting" | "ending";
export function reportAssignments(assignments:Assignment[],kind:ReportKind="directory",ministry="",search="",now=new Date()) {
 const today=new Date(now.getFullYear(),now.getMonth(),now.getDate());
 const end=new Date(today);end.setMonth(end.getMonth()+6);
 const query=search.trim().toLowerCase();
 return assignments.filter(a=>isCurrent(a)&&a.is_public
  &&(!ministry||a.role_name===ministry)
  &&(kind!=="awaiting"||(a.requires_vote&&!a.vote_date))
  &&(kind!=="ending"||(!!a.end_date&&new Date(a.end_date+"T00:00:00")>=today&&new Date(a.end_date+"T00:00:00")<=end))
  &&[a.role_name,a.sub_role_name,a.person_name,a.term_name,a.note_is_public?a.notes:""].some(value=>(value??"").toLowerCase().includes(query)))
  .sort((a,b)=>a.role_name.localeCompare(b.role_name)||(a.leadership_rank??0)-(b.leadership_rank??0)||a.last_name?.localeCompare(b.last_name??"")||a.person_name.localeCompare(b.person_name));
}
export function ChurchReport({supabase,profile,assignments}:{supabase:SupabaseClient;profile:Profile;assignments:Assignment[]}){
 const [filter,setFilter]=useState("");const [kind,setKind]=useState<ReportKind>("directory");const [ministry,setMinistry]=useState("");
 const logo=useChurchLogo(supabase,profile.church_id);const frame=useRef<HTMLIFrameElement>(null);const name=profile.churches?.name??'Ministry Volunteers';
 const current=reportAssignments(assignments,kind,ministry,filter);
 const title=kind==="awaiting"?"Awaiting Church Vote":kind==="ending"?"Terms Ending in Six Months":"Volunteer Ministry Directory";
 const ministries=[...new Set(assignments.filter(isCurrent).map(a=>a.role_name))].sort();
 const groups=Array.from(new Set(current.map(a=>a.role_name)),role=>({role,rows:current.filter(a=>a.role_name===role)}));
 const sections=groups.map(({role,rows})=>`<table class="ministry-report"><thead><tr><th class="ministry-heading" colspan="5"><h2>${escapeHTML(role)}</h2></th></tr><tr><th>Position</th><th>Volunteer</th><th>Term End</th><th>Voted</th><th>Approved Note</th></tr></thead><tbody>${rows.map(a=>`<tr><td>${escapeHTML(a.sub_role_name??'Team member')}</td><td>${escapeHTML(a.person_name)}</td><td>${escapeHTML(formatDate(a.end_date))}</td><td>${escapeHTML(a.vote_date?formatDate(a.vote_date):"—")}</td><td>${escapeHTML(a.note_is_public?a.notes??'':'')}</td></tr>`).join('')}</tbody></table>`).join('');
 const html=`<!doctype html><html><head><meta charset="utf-8"><title>${escapeHTML(name)} — ${title}</title><style>body{font:14px system-ui;color:#142b3a;background:#fff;margin:0;padding:28px;line-height:1.5}header{display:flex;align-items:center;gap:20px;margin-bottom:24px;padding-bottom:16px;border-bottom:1px solid #d6e2ea;background:#fff}img{max-width:112px;max-height:88px;object-fit:contain}h1{font-size:23px;line-height:1.25;margin:0}p{margin:8px 0}table{margin:0 0 24px;width:100%;border-collapse:collapse;table-layout:fixed}th,td{text-align:left;padding:10px 12px;border-bottom:1px solid #d6e2ea;vertical-align:top;overflow-wrap:anywhere}th{background:#f6f8fa;color:#123e5f}.ministry-heading{padding:10px 12px;background:#f6f8fa}.ministry-heading h2{font-size:18px;line-height:1.3;margin:0}thead{display:table-header-group;break-inside:avoid;break-after:avoid}tr{break-inside:avoid}@page{size:landscape;margin:16mm}@media print{body{padding:0}}</style></head><body><header>${logo?`<img src="${escapeHTML(logo)}" alt="Church logo">`:''}<div><h1>${escapeHTML(name)}</h1><p>${title}</p></div></header>${sections}${!current.length?'<p>No assignments match these report options.</p>':''}</body></html>`;
 return <><SectionHeading title="Reports" detail="Choose a report, narrow it if needed, then print or save the preview as a PDF." /><section className="admin-card admin-report-card">
 <div className="admin-report-controls"><div className="admin-report-options">
 <label>Report<select value={kind} onChange={e=>setKind(e.target.value as ReportKind)}><option value="directory">Ministry directory</option><option value="awaiting">Awaiting church vote</option><option value="ending">Terms ending in six months</option></select></label>
 <label>Ministry<select value={ministry} onChange={e=>setMinistry(e.target.value)}><option value="">All ministries</option>{ministries.map(m=><option key={m}>{m}</option>)}</select></label>
 <label>Search within report<input value={filter} onChange={e=>setFilter(e.target.value)} placeholder="Volunteer, position, term, or approved note"/></label>
 </div><div className="admin-report-actions"><p role="status">{current.length} {current.length===1?'assignment':'assignments'} included</p><button className="button" onClick={()=>{setKind("directory");setMinistry("");setFilter("");}}>Reset Filters</button><button className="button button-primary" onClick={()=>frame.current?.contentWindow?.print()}>Print / Save PDF</button></div></div>
 <iframe ref={frame} className="admin-report-frame" sandbox="allow-same-origin allow-modals" srcDoc={html} title={`${name} report preview`}/><p className="admin-report-note">Your church’s name and uploaded logo appear on the report. Only approved notes are included; contact details and ordination status stay private.</p></section></>;
}
