"use client";

import { useEffect, useMemo, useState } from "react";

export type DirectoryEntry = {
  id: string;
  person_name: string;
  last_name: string;
  first_name: string;
  role_name: string;
  sub_role_name: string | null;
  leadership_rank: number;
  term_name: string | null;
  start_date: string | null;
  end_date: string | null;
  vote_date: string | null;
};

type EndingWindow = "all" | "6" | "12";

const previewEntries: DirectoryEntry[] = [
  {
    id: "preview-1",
    person_name: "Jordan Anderson",
    first_name: "Jordan",
    last_name: "Anderson",
    role_name: "Deacon",
    sub_role_name: "Head",
    leadership_rank: 10,
    term_name: "July 26 - June 28",
    start_date: "2026-07-01",
    end_date: "2028-06-30",
    vote_date: "2026-06-20",
  },
  {
    id: "preview-2",
    person_name: "Morgan Brooks",
    first_name: "Morgan",
    last_name: "Brooks",
    role_name: "Deacon",
    sub_role_name: "Assistant Head",
    leadership_rank: 30,
    term_name: "July 26 - June 28",
    start_date: "2026-07-01",
    end_date: "2028-06-30",
    vote_date: "2026-06-20",
  },
  {
    id: "preview-3",
    person_name: "Taylor Chen",
    first_name: "Taylor",
    last_name: "Chen",
    role_name: "Deacon",
    sub_role_name: "Volunteer",
    leadership_rank: 100,
    term_name: "July 26 - June 28",
    start_date: "2026-07-01",
    end_date: "2028-06-30",
    vote_date: null,
  },
  {
    id: "preview-4",
    person_name: "Avery Davis",
    first_name: "Avery",
    last_name: "Davis",
    role_name: "Welcome Team",
    sub_role_name: "Leader",
    leadership_rank: 10,
    term_name: "Jan 26 - Dec 27",
    start_date: "2026-01-01",
    end_date: "2027-12-31",
    vote_date: null,
  },
  {
    id: "preview-5",
    person_name: "Riley Evans",
    first_name: "Riley",
    last_name: "Evans",
    role_name: "Welcome Team",
    sub_role_name: "Volunteer",
    leadership_rank: 100,
    term_name: "Jan 26 - Dec 27",
    start_date: "2026-01-01",
    end_date: "2027-12-31",
    vote_date: null,
  },
];

export function VolunteerDirectory({
  embedded = false,
  projectUrl,
  publishableKey,
}: {
  embedded?: boolean;
  projectUrl?: string;
  publishableKey?: string;
}) {
  const [entries, setEntries] = useState<DirectoryEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isPreview, setIsPreview] = useState(false);
  const [search, setSearch] = useState("");
  const [role, setRole] = useState("all");
  const [endingWindow, setEndingWindow] = useState<EndingWindow>("all");

  useEffect(() => {
    const controller = new AbortController();

    async function loadDirectory() {
      if (!projectUrl || !publishableKey) {
        setEntries(previewEntries);
        setIsPreview(true);
        setLoading(false);
        return;
      }

      try {
        const base = projectUrl.replace(/\/+$/, "");
        const pageSize = 1000;
        let offset = 0;
        const data: DirectoryEntry[] = [];
        while (true) {
          const params = new URLSearchParams({
            select: "*",
            order:
              "role_name.asc,leadership_rank.asc,last_name.asc,first_name.asc",
            limit: String(pageSize),
            offset: String(offset),
          });
          const response = await fetch(
            `${base}/rest/v1/public_directory_entries?${params}`,
            {
              headers: {
                apikey: publishableKey,
                Accept: "application/json",
              },
              signal: controller.signal,
            },
          );
          if (!response.ok) {
            throw new Error(`Directory request failed (${response.status}).`);
          }
          const page = (await response.json()) as DirectoryEntry[];
          data.push(...page);
          if (page.length < pageSize) break;
          offset += pageSize;
        }
        setEntries(data);
      } catch (caught) {
        if (controller.signal.aborted) return;
        setError(
          caught instanceof Error
            ? caught.message
            : "The directory could not be loaded.",
        );
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    }

    loadDirectory();
    return () => controller.abort();
  }, [projectUrl, publishableKey]);

  const roles = useMemo(
    () =>
      [...new Set(entries.map((entry) => entry.role_name))].sort((a, b) =>
        a.localeCompare(b),
      ),
    [entries],
  );

  const filtered = useMemo(() => {
    const normalizedSearch = search.trim().toLocaleLowerCase();
    const today = startOfToday();
    const endingBy =
      endingWindow === "all"
        ? null
        : addMonths(today, Number(endingWindow));

    return entries
      .filter((entry) => {
        if (role !== "all" && entry.role_name !== role) return false;
        if (
          normalizedSearch &&
          ![
            entry.person_name,
            entry.role_name,
            entry.sub_role_name ?? "",
            entry.term_name ?? "",
          ].some((value) =>
            value.toLocaleLowerCase().includes(normalizedSearch),
          )
        ) {
          return false;
        }
        if (endingBy) {
          if (!entry.end_date) return false;
          const endDate = localDate(entry.end_date);
          if (endDate < today || endDate > endingBy) return false;
        }
        return true;
      })
      .sort(compareEntries);
  }, [endingWindow, entries, role, search]);

  const grouped = useMemo(() => {
    const result = new Map<string, DirectoryEntry[]>();
    for (const entry of filtered) {
      const existing = result.get(entry.role_name) ?? [];
      existing.push(entry);
      result.set(entry.role_name, existing);
    }
    return [...result.entries()];
  }, [filtered]);

  function clearFilters() {
    setSearch("");
    setRole("all");
    setEndingWindow("all");
  }

  function exportCSV() {
    const headers = [
      "Ministry Role",
      "Volunteer",
      "Position",
      "Term",
      "Term Start",
      "Term End",
      "Vote Date",
    ];
    const rows = filtered.map((entry) => [
      entry.role_name,
      entry.person_name,
      entry.sub_role_name ?? "Volunteer",
      entry.term_name ?? "",
      entry.start_date ?? "",
      entry.end_date ?? "",
      entry.vote_date ?? "",
    ]);
    const csv = [headers, ...rows]
      .map((row) => row.map(csvCell).join(","))
      .join("\r\n");
    const blob = new Blob([`\uFEFF${csv}`], {
      type: "text/csv;charset=utf-8",
    });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = "Riverview-Volunteer-Directory.csv";
    link.click();
    URL.revokeObjectURL(link.href);
  }

  return (
    <main className={embedded ? "directory-shell embedded" : "directory-shell"}>
      <header className="site-header">
        <div className="brand-lockup">
          <BrandMark />
          <div>
            <p className="eyebrow">Pasco Riverview Adventist Church</p>
            <h1>Volunteer ministry directory</h1>
          </div>
        </div>
        {!embedded && (
          <p className="intro">
            Find volunteers by person or ministry, review leadership positions,
            and identify terms nearing completion.
          </p>
        )}
      </header>

      <section className="filter-panel" aria-label="Directory filters">
        <label className="search-field">
          <span>Search</span>
          <span className="input-shell">
            <SearchIcon />
            <input
              type="search"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Person, role, position, or term"
            />
          </span>
        </label>

        <label>
          <span>Ministry role</span>
          <select value={role} onChange={(event) => setRole(event.target.value)}>
            <option value="all">All roles</option>
            {roles.map((roleName) => (
              <option value={roleName} key={roleName}>
                {roleName}
              </option>
            ))}
          </select>
        </label>

        <label>
          <span>Term ending</span>
          <select
            value={endingWindow}
            onChange={(event) =>
              setEndingWindow(event.target.value as EndingWindow)
            }
          >
            <option value="all">Any time</option>
            <option value="6">Next 6 months</option>
            <option value="12">Next 12 months</option>
          </select>
        </label>

        <div className="filter-actions">
          <button className="button secondary" type="button" onClick={clearFilters}>
            Clear
          </button>
          <button className="button secondary" type="button" onClick={exportCSV}>
            <DownloadIcon />
            CSV
          </button>
          <button
            className="button primary"
            type="button"
            onClick={() => window.print()}
          >
            <PrintIcon />
            Print / PDF
          </button>
        </div>
      </section>

      <section className="directory-summary" aria-live="polite">
        <p>
          <strong>{filtered.length}</strong>{" "}
          {filtered.length === 1 ? "assignment" : "assignments"}
          {role !== "all" ? ` in ${role}` : ""}
        </p>
        <p className="sort-note">
          Leadership positions first, then alphabetical by last name
        </p>
      </section>

      {isPreview && (
        <div className="notice preview-notice" role="status">
          <strong>Preview data:</strong> connect the hosted site to Supabase to
          show the church directory.
        </div>
      )}
      {error && (
        <div className="notice error-notice" role="alert">
          <strong>Directory unavailable.</strong> {error}
        </div>
      )}

      {loading ? (
        <LoadingDirectory />
      ) : grouped.length === 0 ? (
        <section className="empty-state">
          <span aria-hidden="true">⌕</span>
          <h2>No matching assignments</h2>
          <p>Clear a filter or try a broader search.</p>
        </section>
      ) : (
        <div className="role-groups">
          {grouped.map(([roleName, roleEntries]) => (
            <section className="role-group" key={roleName}>
              <div className="role-heading">
                <h2>{roleName}</h2>
                <span>{roleEntries.length}</span>
              </div>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Volunteer</th>
                      <th>Position</th>
                      <th>Term</th>
                      <th>Term end</th>
                      <th>Vote date</th>
                    </tr>
                  </thead>
                  <tbody>
                    {roleEntries.map((entry) => (
                      <tr key={entry.id}>
                        <td data-label="Volunteer">
                          <strong>{entry.person_name}</strong>
                        </td>
                        <td data-label="Position">
                          <PositionBadge entry={entry} />
                        </td>
                        <td data-label="Term">{entry.term_name ?? "No term"}</td>
                        <td data-label="Term end">
                          {formatDate(entry.end_date)}
                        </td>
                        <td data-label="Vote date">
                          {formatDate(entry.vote_date)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          ))}
        </div>
      )}

      <footer>
        <p>
          Public directory records include names and ministry assignments only.
          Contact information remains private in the staff app.
        </p>
        <p className="print-generated">
          Printed {new Intl.DateTimeFormat("en-US", { dateStyle: "long" }).format(new Date())}
        </p>
      </footer>
    </main>
  );
}

function PositionBadge({ entry }: { entry: DirectoryEntry }) {
  const leadership = entry.leadership_rank < 100;
  return (
    <span className={leadership ? "position leadership" : "position"}>
      {entry.sub_role_name ?? "Volunteer"}
    </span>
  );
}

function LoadingDirectory() {
  return (
    <div className="loading-list" aria-label="Loading directory">
      {[0, 1, 2].map((index) => (
        <div className="loading-row" key={index}>
          <span />
          <span />
          <span />
        </div>
      ))}
    </div>
  );
}

function BrandMark() {
  return (
    <svg
      className="brand-mark"
      viewBox="0 0 56 56"
      role="img"
      aria-label="Riverview ministry mark"
    >
      <path d="M28 4a24 24 0 1 0 24 24A24 24 0 0 0 28 4Z" fill="#0e4b3c" />
      <path
        d="M17 35c5-8 12-13 22-16-3 5-5 10-5 17"
        fill="none"
        stroke="#e0ad55"
        strokeLinecap="round"
        strokeWidth="4"
      />
      <path
        d="M14 39c8-2 17-2 28 1"
        fill="none"
        stroke="#fff"
        strokeLinecap="round"
        strokeWidth="3"
      />
    </svg>
  );
}

function SearchIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="m21 21-4.3-4.3m2.3-5.2a7.5 7.5 0 1 1-15 0 7.5 7.5 0 0 1 15 0Z" />
    </svg>
  );
}

function DownloadIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 3v12m0 0 4-4m-4 4-4-4M4 19h16" />
    </svg>
  );
}

function PrintIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M7 9V3h10v6M7 17H5a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-2m-10-4h10v8H7v-8Z" />
    </svg>
  );
}

function compareEntries(left: DirectoryEntry, right: DirectoryEntry) {
  return (
    left.role_name.localeCompare(right.role_name) ||
    left.leadership_rank - right.leadership_rank ||
    left.last_name.localeCompare(right.last_name) ||
    left.first_name.localeCompare(right.first_name)
  );
}

function startOfToday() {
  const date = new Date();
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addMonths(date: Date, count: number) {
  const result = new Date(date);
  result.setMonth(result.getMonth() + count);
  return result;
}

function localDate(value: string) {
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day);
}

function formatDate(value: string | null) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(localDate(value));
}

function csvCell(value: string) {
  return `"${value.replaceAll('"', '""')}"`;
}
