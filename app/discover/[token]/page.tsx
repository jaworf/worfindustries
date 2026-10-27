
import {DiscoveryApp} from "../../discovery/participant";
export const dynamic="force-dynamic";
export const metadata={title:"Discover your ministry | Ministry Volunteers"};
export default async function Page({params}:{params:Promise<{token:string}>}){const {token}=await params;return <DiscoveryApp token={token} projectUrl={process.env.SUPABASE_URL} publishableKey={process.env.SUPABASE_PUBLISHABLE_KEY}/>;}
