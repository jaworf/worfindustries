import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Support | Ministry Volunteers",
  description: "Support for the Ministry Volunteers app.",
};

export default function SupportPage() {
  return (
    <main className="support-shell">
      <section className="support-card">
        <img
          src="/ministry-logo.png"
          alt="Ministry Volunteers logo"
          className="support-logo"
        />
        <p className="eyebrow">Ministry Volunteers</p>
        <h1>App Support</h1>
        <p>
          Need help signing in, connecting Planning Center, importing data, or
          managing volunteer assignments? Contact the app administrator.
        </p>
        <a
          className="button button-primary"
          href="mailto:jason.worf@riverviewadventist.org?subject=Ministry%20Volunteers%20Support"
        >
          Email Support
        </a>
        <p className="support-email">
          <a href="mailto:jason.worf@riverviewadventist.org">
            jason.worf@riverviewadventist.org
          </a>
        </p>
        <div className="support-details">
          <h2>Helpful details to include</h2>
          <ul>
            <li>Your church name and the email used to sign in</li>
            <li>The device and operating system you are using</li>
            <li>What you expected to happen and any error message shown</li>
          </ul>
          <p>Do not send passwords or Planning Center API secrets by email.</p>
        </div>
        <p><a href="/admin">Open the web app</a></p>
      </section>
    </main>
  );
}

