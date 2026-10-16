export function SectionHeading({ title, detail }: { title: string; detail: string }) {
  return (
    <header className="admin-section-heading">
      <div>
        <p className="eyebrow">Riverview Ministry Volunteers</p>
        <h2>{title}</h2>
      </div>
      <p>{detail}</p>
    </header>
  );
}

