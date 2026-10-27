import { ChurchAccess } from "./church-access";
export const dynamic="force-dynamic";
export const metadata={title:"Platform Support | Ministry Volunteers"};
export default function PlatformPage(){return <ChurchAccess mode="platform" projectUrl={process.env.SUPABASE_URL} publishableKey={process.env.SUPABASE_PUBLISHABLE_KEY}/>;}
