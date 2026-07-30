import { VolunteerDirectory } from "./directory-client";

export const dynamic = "force-dynamic";

export default function Home() {
  return (
    <VolunteerDirectory
      projectUrl={process.env.SUPABASE_URL}
      publishableKey={process.env.SUPABASE_PUBLISHABLE_KEY}
    />
  );
}
