import type { Metadata } from "next";
import { PasswordReset } from "./password-reset-client";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Set Up Password | Riverview Ministry Volunteers",
  description: "Choose a password for the Riverview Ministry Volunteers app.",
};

export default function ResetPasswordPage() {
  return (
    <PasswordReset
      projectUrl={process.env.SUPABASE_URL}
      publishableKey={process.env.SUPABASE_PUBLISHABLE_KEY}
    />
  );
}
