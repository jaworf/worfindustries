import {MinistryAdmin} from "../../../admin/admin-client";
import {loadEmbedConfig} from "../../config";
export const dynamic="force-dynamic";
export default async function EmbeddedApp({params}:{params:Promise<{church:string}>}){
 const {church}=await params;
 const config=await loadEmbedConfig(church,"app",process.env.SUPABASE_URL,process.env.SUPABASE_PUBLISHABLE_KEY);
 if(!config)return <main className="admin-login-shell"><section className="admin-login-card"><h1>Website embed is not enabled</h1><p>A church admin must enable the login-required embed and save the approved website address in Settings.</p></section></main>;
 return <MinistryAdmin projectUrl={process.env.SUPABASE_URL} publishableKey={process.env.SUPABASE_PUBLISHABLE_KEY} expectedChurchSlug={church} embedded churchName={config.name}/>;
}
