"use client";
import { useEffect, useId, useRef, useState } from "react";
export type SearchOption = { value: string; label: string; detail?: string };
export function SearchSelect({
  label,
  value,
  options,
  onChange,
  disabled = false,
  required = false,
  placeholder = "Type to search…",
  onCreate,
  createLabel = "Create new",
}: {
  label: string;
  value: string;
  options: SearchOption[];
  onChange: (value: string) => void;
  disabled?: boolean;
  required?: boolean;
  placeholder?: string;
  onCreate?: (name: string) => void;
  createLabel?: string;
}) {
  const id = useId(),
    input = useRef<HTMLInputElement>(null);
  const [open, setOpen] = useState(false),
    [query, setQuery] = useState<string | null>(null),
    [active, setActive] = useState(0);
  const selected = options.find((o) => o.value === value);
  const matches = options.filter(
    (o) =>
      query === null ||
      [o.label, o.detail].some((v) =>
        v?.toLowerCase().includes(query.toLowerCase()),
      ),
  );
  const canCreate =
    !!onCreate &&
    !!query?.trim() &&
    !options.some(
      (o) => o.label.trim().toLowerCase() === query.trim().toLowerCase(),
    );
  useEffect(() => {
    input.current?.setCustomValidity(
      (required && !value) || (query !== null && !!query.trim() && !value)
        ? "Choose an option from the list."
        : "",
    );
  }, [value, query, required]);
  function choose(option: SearchOption) {
    onChange(option.value);
    setQuery(null);
    setOpen(false);
    setActive(0);
  }
  return (
    <div
      className="search-select"
      onBlur={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget)) setOpen(false);
      }}
    >
      <label htmlFor={id}>{label}</label>
      <div className="search-select-input">
        <input
          ref={input}
          id={id}
          role="combobox"
          autoComplete="off"
          aria-autocomplete="list"
          aria-expanded={open}
          aria-controls={id + "-options"}
          aria-activedescendant={
            open && matches[active] ? id + "-" + active : undefined
          }
          disabled={disabled}
          required={required}
          placeholder={placeholder}
          value={query ?? selected?.label ?? ""}
          onFocus={() => setOpen(true)}
          onChange={(e) => {
            setQuery(e.target.value);
            onChange("");
            setOpen(true);
            setActive(0);
          }}
          onKeyDown={(e) => {
            if (e.key === "ArrowDown" || e.key === "ArrowUp") {
              e.preventDefault();
              setOpen(true);
              setActive((n) =>
                Math.max(
                  0,
                  Math.min(
                    matches.length - 1,
                    n + (e.key === "ArrowDown" ? 1 : -1),
                  ),
                ),
              );
            }
            if (e.key === "Enter" && open) {
              e.preventDefault();
              if (matches[active]) choose(matches[active]);
              else if (canCreate) {
                onCreate?.(query!.trim());
                setQuery(null);
                setOpen(false);
              }
            }
            if (e.key === "Escape") {
              setOpen(false);
              setQuery(null);
            }
          }}
        />
        <button
          type="button"
          disabled={disabled}
          aria-label={"Show all " + label.toLowerCase() + " options"}
          aria-expanded={open}
          onClick={() => {
            setQuery(null);
            setActive(0);
            setOpen(!open || query !== null);
          }}
        >
          ▾
        </button>
      </div>
      {open && !disabled && (
        <div className="search-select-popup">
          <div
            role="listbox"
            id={id + "-options"}
            aria-label={label + " options"}
          >
            {matches.map((o, i) => (
              <button
                type="button"
                role="option"
                id={id + "-" + i}
                key={o.value}
                aria-selected={o.value === value}
                className={active === i ? "highlighted" : ""}
                onClick={() => choose(o)}
              >
                <strong>{o.label}</strong>
                {o.detail && <small>{o.detail}</small>}
              </button>
            ))}
            {!matches.length && <p>No matches.</p>}
          </div>
          {canCreate && (
            <button
              type="button"
              className="search-select-create"
              onClick={() => {
                onCreate?.(query!.trim());
                setQuery(null);
                setOpen(false);
              }}
            >
              {createLabel}: “{query}”
            </button>
          )}
        </div>
      )}
    </div>
  );
}
