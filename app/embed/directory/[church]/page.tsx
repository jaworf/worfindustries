import {VolunteerDirectory} from "../../../directory-client";
import {loadEmbedConfig} from "../../config";
export const dynamic="force-dynamic";
export default async function EmbeddedDirectory({params}:{params:Promise<{church:string}>}){
 const {church}=await params;
 const config=await loadEmbedConfig(church,"directory",process.env.SUPABASE_URL,process.env.SUPABASE_PUBLISHABLE_KEY);
 if(!config)return <main className="admin-login-shell"><section className="admin-login-card"><h1>Public directory embed is not enabled</h1><p>Ask your church admin to review public-directory publishing in Settings.</p></section></main>;
 return <VolunteerDirectory embedded churchSlug={church} churchName={config.name} projectUrl={process.env.SUPABASE_URL} publishableKey={process.env.SUPABASE_PUBLISHABLE_KEY}/>;
}
