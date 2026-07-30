import { VolunteerDirectory } from "../directory-client";

export const dynamic = "force-dynamic";

export default function EmbedDirectory() {
  return (
    <VolunteerDirectory
      embedded
      projectUrl={process.env.SUPABASE_URL}
      publishableKey={process.env.SUPABASE_PUBLISHABLE_KEY}
    />
  );
}
