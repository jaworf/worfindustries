export type EmbedConfig = { name:string;slug:string;allowed_origins:string[] };
export async function loadEmbedConfig(church:string,mode:"app"|"directory",projectUrl?:string,key?:string):Promise<EmbedConfig|null>{
 if(!projectUrl||!key||!/^[a-z0-9][a-z0-9-]{0,79}$/.test(church)) return null;
 try {
  const response=await fetch(`${projectUrl.replace(/\/+$/,"")}/rest/v1/rpc/website_embed_config`,{method:"POST",headers:{apikey:key,"Content-Type":"application/json"},body:JSON.stringify({p_slug:church,p_mode:mode}),cache:"no-store",signal:AbortSignal.timeout(5000)});
  if(!response.ok)return null;
  const result=await response.json();
  return result?.slug===church&&typeof result.name==="string"&&Array.isArray(result.allowed_origins)?result:null;
 }catch{return null;}
}
