import type { Metadata } from "next";
import { MinistryAdmin } from "./admin-client";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Ministry Volunteers | Church Administration",
  description:
    "Securely manage your church’s ministry volunteers from a phone, tablet, or computer.",
};

export default function AdminPage() {
  return (
    <MinistryAdmin
      projectUrl={process.env.SUPABASE_URL}
      publishableKey={process.env.SUPABASE_PUBLISHABLE_KEY}
    />
  );
}
