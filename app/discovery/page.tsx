
import {DiscoveryApp} from "./participant";
export const dynamic="force-dynamic";
export const metadata={title:"My Ministry Profile | Ministry Volunteers"};
export default function Page(){return <DiscoveryApp projectUrl={process.env.SUPABASE_URL} publishableKey={process.env.SUPABASE_PUBLISHABLE_KEY}/>;}
