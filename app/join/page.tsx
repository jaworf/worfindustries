import { ChurchAccess } from "../platform/church-access";
export const dynamic="force-dynamic";
export const metadata={title:"Apply | Ministry Volunteers"};
export default function JoinPage(){return <ChurchAccess mode="join" projectUrl={process.env.SUPABASE_URL} publishableKey={process.env.SUPABASE_PUBLISHABLE_KEY}/>;}
