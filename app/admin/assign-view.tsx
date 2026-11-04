"use client";
import {SearchSelect} from "./search-select";
import {useState, type FormEvent} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
import {type AssignmentRoute, type Snapshot, type MutationRunner, ordinationKind, ordinationField, personName, formatDate, todayISO, ordinationLabel} from "./admin-shared";
import {SectionHeading} from "./section-heading";
export function AssignView({
  initialRoute,
  supabase,
  snapshot,
  canEdit,
  working,
  mutate,
}: {
  initialRoute: AssignmentRoute;
  supabase: SupabaseClient;
  snapshot: Snapshot;
  canEdit: boolean;
  working: boolean;
  mutate: MutationRunner;
}) {
  const [newPerson, setNewPerson] = useState(false);
  const [personId, setPersonId] = useState(initialRoute.personId ?? "");
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [ministryId, setMinistryId] = useState(initialRoute.ministryId ?? "");
  const [positionId, setPositionId] = useState("");
  const [termId, setTermId] = useState("");
  const [voteDate, setVoteDate] = useState("");
  const [notes, setNotes] = useState("");
  const [notePublic, setNotePublic] = useState(false);
  const [assignmentPublic, setAssignmentPublic] = useState(true);
  const [personPublic, setPersonPublic] = useState(true);
  const [newPositionName, setNewPositionName] = useState("");
  const [newPositionVote, setNewPositionVote] = useState(false);
  const [ordinationOverride, setOrdinationOverride] = useState<{ key: string; value: boolean } | null>(null);
  const [formError, setFormError] = useState<string | null>(null);

  const activeMinistries = snapshot.ministries.filter((item) => item.is_active);
  const selectedMinistry = activeMinistries.find((item) => item.id === ministryId);
  const selectedPerson = snapshot.people.find((item) => item.id === personId);
  const availablePositions = snapshot.positions.filter(
    (item) => item.is_active && item.role_id === ministryId,
  );
  const selectedPosition = availablePositions.find((item) => item.id === positionId);
  const kind = ordinationKind(selectedMinistry?.name);
  const requiresVote = Boolean(
    positionId && (selectedMinistry?.requires_vote ||
      selectedPosition?.requires_vote ||
      (positionId === "add" && newPositionVote)),
  );

  const ordinationKey = `${newPerson ? "new" : personId}:${kind ?? "none"}`;
  const ordained = ordinationOverride?.key === ordinationKey
    ? ordinationOverride.value
    : Boolean(!newPerson && kind && selectedPerson?.[ordinationField(kind)]);
  function changeMinistry(value: string) {
    setMinistryId(value);
    setPositionId("");
    setNewPositionName("");
    setNewPositionVote(false);
    setOrdinationOverride(null);
  }
  function changePerson(value: string) {
    setPersonId(value);
    setOrdinationOverride(null);
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setFormError(null);
    if (!canEdit) return setFormError("Your account has view-only access.");
    if (!ministryId) return setFormError("Choose a ministry.");
    if (newPerson && (!firstName.trim() || !lastName.trim())) {
      return setFormError("Enter the new person's first and last name.");
    }
    if (!newPerson && !personId) return setFormError("Choose a person.");
    if (positionId === "add" && !newPositionName.trim()) {
      return setFormError("Enter the new position name.");
    }
    if (requiresVote && !termId) return setFormError("A term is required for a voted role.");

    const succeeded = await mutate("Volunteer assignment saved.", async () => {
      let savedPersonId = personId;
      if (newPerson) {
        const { data, error } = await supabase
          .from("people")
          .insert({
            first_name: firstName.trim(),
            last_name: lastName.trim(),
            email: email.trim() || null,
            mobile_phone: phone.trim() || null,
            is_active: true,
            is_public: personPublic,
            is_ordained_deacon: kind === "deacon" ? ordained : false,
            is_ordained_deaconess: kind === "deaconess" ? ordained : false,
            is_ordained_elder: kind === "elder" ? ordained : false,
          })
          .select("id")
          .single();
        if (error) throw error;
        savedPersonId = data.id;
      } else if (kind) {
        const { error } = await supabase
          .from("people")
          .update({ [ordinationField(kind)]: ordained })
          .eq("id", savedPersonId);
        if (error) throw error;
      }

      let savedPositionId = positionId;
      if (positionId === "add") {
        const { data, error } = await supabase
          .from("sub_roles")
          .insert({
            role_id: ministryId,
            name: newPositionName.trim(),
            leadership_rank: 100,
            requires_vote: newPositionVote,
            is_active: true,
          })
          .select("id")
          .single();
        if (error) throw error;
        savedPositionId = data.id;
      }

      const { error } = await supabase.from("assignments").insert({
        person_id: savedPersonId,
        role_id: ministryId,
        sub_role_id: savedPositionId || null,
        term_id: savedPositionId ? termId || null : null,
        vote_date: savedPositionId ? voteDate || null : null,
        notes: notes.trim() || null,
        note_is_public: Boolean(notes.trim()) && notePublic,
        status: "active",
        is_public: assignmentPublic,
      });
      if (error) throw error;
    });

    if (succeeded) {
      setPersonId("");
      setFirstName("");
      setLastName("");
      setEmail("");
      setPhone("");
      setMinistryId("");
      setPositionId("");
      setTermId("");
      setVoteDate("");
      setNotes("");
      setNotePublic(false);
      setOrdinationOverride(null);
    }
  }

  return (
    <>
      <SectionHeading
        title="Assign a Volunteer"
        detail="Choose an existing person or create a new person, then record the placement."
      />
      <form className="admin-card admin-editor-form" onSubmit={submit}>
        <fieldset disabled={!canEdit || working}>
          <legend>Volunteer</legend>
          <label className="admin-check-row">
            <input type="checkbox" checked={newPerson} onChange={(event) => {setNewPerson(event.target.checked);setOrdinationOverride(null);}} />
            Enter a new person
          </label>
          {newPerson ? (
            <div className="admin-form-grid">
              <label>
                First name
                <input value={firstName} onChange={(event) => setFirstName(event.target.value)} required />
              </label>
              <label>
                Last name
                <input value={lastName} onChange={(event) => setLastName(event.target.value)} required />
              </label>
              <label>
                Email
                <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} />
              </label>
              <label>
                Mobile phone
                <input type="tel" value={phone} onChange={(event) => setPhone(event.target.value)} />
              </label>
              <label className="admin-check-row full">
                <input type="checkbox" checked={personPublic} onChange={(event) => setPersonPublic(event.target.checked)} />
                Allow this person&apos;s name in the public directory
              </label>
            </div>
          ) : (
            <SearchSelect label="Volunteer" value={personId} required options={snapshot.people.filter(p=>p.is_active).map(p=>({value:p.id,label:personName(p),detail:[p.email,p.mobile_phone,p.membership_status].filter(Boolean).join(' · ')}))} onChange={changePerson}/>
          )}
        </fieldset>

        <fieldset disabled={!canEdit || working}>
          <legend>Ministry placement</legend>
          <div className="admin-form-grid">
            <SearchSelect label="Ministry" value={ministryId} required options={activeMinistries.map(m=>({value:m.id,label:m.name}))} onChange={changeMinistry}/>
            <SearchSelect label="Position" value={positionId} disabled={!ministryId} options={[{value:'',label:'No position — team member'},...availablePositions.map(p=>({value:p.id,label:p.name})),{value:'add',label:'＋ Add a position…'}]} onChange={v=>{setPositionId(v);if(!v){setTermId('');setVoteDate('');}}}/>
            {positionId === "add" && (
              <>
                <label>
                  New position name
                  <input value={newPositionName} onChange={(event) => setNewPositionName(event.target.value)} required />
                </label>
                <label className="admin-check-row admin-check-bottom">
                  <input type="checkbox" checked={newPositionVote} onChange={(event) => setNewPositionVote(event.target.checked)} />
                  Position requires church vote
                </label>
              </>
            )}
            <SearchSelect label={requiresVote?'Term (required)':'Term'} value={termId} disabled={!positionId} options={[{value:'',label:requiresVote?'Choose a term':'No term'},...snapshot.terms.filter(t=>t.is_active).map(t=>({value:t.id,label:t.name,detail:t.end_date?'Ends '+formatDate(t.end_date):undefined}))]} onChange={setTermId}/>
            {positionId && (requiresVote || voteDate) && (
              <label>
                Church vote date (optional)
                <input type="date" value={voteDate} onChange={(event) => setVoteDate(event.target.value)} />
              </label>
            )}
          </div>
          {positionId && (
            <button type="button" className="button button-link align-left" onClick={() => setVoteDate(voteDate ? "" : todayISO())}>
              {voteDate ? "Remove optional vote date" : "Add an optional vote date"}
            </button>
          )}
        </fieldset>

        {kind && (
          <fieldset disabled={!canEdit || working} className="admin-ordination-fieldset">
            <legend>Ordination</legend>
            <label className="admin-check-row">
              <input type="checkbox" checked={ordained} onChange={(event) => setOrdinationOverride({key: ordinationKey, value: event.target.checked})} />
              {ordinationLabel(kind)}
            </label>
            <p>This permanent person record remains after the placement is archived.</p>
          </fieldset>
        )}

        <p>Leave the vote date empty to place a voted role in Needing Votes.</p>
        <fieldset disabled={!canEdit || working}>
          <legend>Assignment details</legend>
          <label>
            Note
            <textarea value={notes} onChange={(event) => setNotes(event.target.value)} rows={4} placeholder="Optional staff note" />
          </label>
          <label className="admin-check-row">
            <input type="checkbox" checked={notePublic} onChange={(event) => setNotePublic(event.target.checked)} disabled={!notes.trim()} />
            Include this note in reports and the public web directory
          </label>
          <label className="admin-check-row">
            <input type="checkbox" checked={assignmentPublic} onChange={(event) => setAssignmentPublic(event.target.checked)} />
            Show this assignment in the public directory
          </label>
        </fieldset>

        {formError && <p className="admin-form-error">{formError}</p>}
        {!canEdit && <p className="admin-readonly">Your viewer account cannot save changes.</p>}
        <button className="button button-primary button-wide" disabled={!canEdit || working}>
          {working ? "Saving…" : "Save Assignment"}
        </button>
      </form>
    </>
  );
}

