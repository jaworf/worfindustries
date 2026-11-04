"use client";
import {useEffect,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
export function iframeCode(url:string,name:string){
 const attr=(v:string)=>v.replace(/&/g,"&amp;").replace(/"/g,"&quot;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
 return `<iframe\n  src="${attr(url)}"\n  title="${attr(name)}"\n  width="100%" height="1100"\n  style="border:0; max-width:100%;"\n  sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-popups-to-escape-sandbox allow-modals allow-downloads"\n  referrerpolicy="strict-origin-when-cross-origin"\n></iframe>`;
}
function CodeBox({label,code}:{label:string;code:string}){
 const [notice,setNotice]=useState("");
 return <div className="embed-code-box"><label>{label}<textarea aria-label={label} readOnly rows={8} value={code} onFocus={e=>e.currentTarget.select()}/></label><button className="button" type="button" onClick={async()=>{try{await navigator.clipboard.writeText(code);setNotice("Copied.");}catch{setNotice("Select the code above and copy it.");}}}>Copy iframe code</button><span role="status">{notice}</span></div>;
}
export function WebsiteEmbedSettings({client,churchName,churchSlug}:{client:SupabaseClient;churchName:string;churchSlug:string}){
 const [origins,setOrigins]=useState(""),[secure,setSecure]=useState(false),[publicEmbed,setPublicEmbed]=useState(false),[published,setPublished]=useState(false),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(""),[notice,setNotice]=useState(""),[base,setBase]=useState("https://ministryvolunteers.worf.app");
 useEffect(()=>{let live=true;void client.rpc("website_embed_settings").then(({data,error})=>{if(!live)return;setBase(window.location.origin);if(error||!data){setError(error?.message??"Website settings could not be loaded.");return;}setOrigins(data.allowed_origins.join("\n"));setSecure(data.secure_enabled);setPublicEmbed(data.public_enabled);setPublished(data.directory_published);setLoading(false);});return()=>{live=false;};},[client]);
 async function save(){
  setError("");setNotice("");setBusy(true);
  try{
   const values=origins.split(/[\s,]+/).filter(Boolean).map(value=>{const url=new URL(value);if(url.protocol!=="https:"||url.username||url.password||url.hostname.includes("*"))throw new Error("Enter HTTPS website addresses, such as https://www.yourchurch.org.");return url.origin.toLowerCase();});
   const {error}=await client.rpc("save_website_embeds",{p_origins:[...new Set(values)],p_secure:secure,p_public:publicEmbed,p_directory_published:published});
   if(error)throw error;
   setOrigins([...new Set(values)].join("\n"));setNotice("Website options saved. Copy the code for your chosen option below.");
  }catch(e){setError(e instanceof Error?e.message:typeof e==="object"&&e&&"message" in e?String(e.message):"Website options could not be saved.");}finally{setBusy(false);}
 }
 return <section className="admin-card website-embeds" id="website-embeds">
  <h3>Put the app on your church’s website</h3>
  <p>The login-required option keeps the full workspace inside your church’s branded webpage. Each person signs in with their own app account and retains their admin, editor or viewer permissions.</p>
  <label>Approved website addresses<textarea rows={3} value={origins} onChange={e=>setOrigins(e.target.value)} disabled={loading||busy} placeholder="https://www.yourchurch.org"/></label>
  <p className="admin-help">Use one HTTPS website address per line. Add both the www and non-www versions if your site uses both. Page paths are removed automatically.</p>
  <div className="embed-options">
   <section className="embed-option-card"><h4>1. Login-required full app — recommended</h4>
    <label className="admin-check-row"><input type="checkbox" checked={secure} disabled={loading||busy} onChange={e=>setSecure(e.target.checked)}/>Allow the full app on approved websites</label>
    <p>The church’s website stays in the browser’s address bar. Church records require an app login; an account from another church cannot open this workspace.</p>
    <CodeBox label="Full-app iframe code" code={iframeCode(`${base}/embed/app/${encodeURIComponent(churchSlug)}`,`${churchName} Ministry Volunteers`)}/>
   </section>
   <section className="embed-option-card"><h4>2. Limited public directory</h4>
    <p>A read-only ministry directory with PDF download and printing. It shows only ministry, volunteer name and term. There are no login or editing controls.</p>
    <label className="admin-check-row"><input type="checkbox" checked={published} disabled={loading||busy} onChange={e=>{setPublished(e.target.checked);if(!e.target.checked)setPublicEmbed(false);}}/>Publish this church’s directory publicly</label>
    <label className="admin-check-row"><input type="checkbox" checked={publicEmbed} disabled={loading||busy||!published} onChange={e=>setPublicEmbed(e.target.checked)}/>Allow this public directory inside approved websites</label>
    <p>Publishing controls public access, including direct directory links. The website switch only allows embedding; turning it off does not unpublish the directory.</p>
    <p><strong>This directory is public.</strong> A password on the containing webpage does not protect the separate iframe URL. Anyone with a public directory link can open it. Turning off public-directory publishing makes those records unavailable to anonymous visitors.</p>
    <CodeBox label="Limited public directory iframe code" code={iframeCode(`${base}/embed/directory/${encodeURIComponent(churchSlug)}`,`${churchName} Limited Public Directory`)}/>
   </section>
  </div>
  <button className="button button-primary" disabled={loading||busy||!churchSlug} onClick={()=>void save()}>{busy?"Saving…":"Save Website Options"}</button>
  {error&&<p role="alert">{error}</p>}{notice&&<p role="status">{notice}</p>}
  <h4>Add it to your website</h4><ol><li>Enter your website address, select the option you want, and save.</li><li>Copy that option’s iframe code.</li><li>Paste it into a Custom HTML or Embed block on your church’s website. Adjust the height if needed.</li></ol>
  <p>We recommend placing the app on a password-protected staff or ministry-team webpage as an extra layer. The full-app option still requires each person’s app login. Never put passwords or login tokens in the iframe code.</p>
  <p className="admin-help">Some browsers restrict sign-in within another website. The embedded sign-in screen includes a link to open the secure app in a separate tab if needed. Account setup, participant assessments and support links may also open separately.</p>
 </section>;
}
