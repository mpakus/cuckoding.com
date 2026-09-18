defmodule CuckodingWeb.KnowledgeReviewLive do
  use CuckodingWeb, :live_view

  alias Cuckoding.Knowledge

  @actor "local-user"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Knowledge review", notice: "", error: "")
     |> load()}
  end

  @impl true
  def handle_event(
        "review",
        %{"candidate_id" => id, "decision" => decision, "reason" => reason},
        socket
      ) do
    result = Knowledge.review_candidate(id, decision, @actor, reason)
    finish(socket, result, "Candidate #{decision}.")
  end

  def handle_event("request-publication", %{"candidate_id" => id}, socket) do
    finish(socket, Knowledge.request_publication(id), "Global publication approval requested.")
  end

  def handle_event(
        "decide-approval",
        %{"approval_id" => id, "decision" => decision, "reason" => reason},
        socket
      ) do
    result = Cuckoding.Workflows.decide_approval(id, decision, @actor, reason)
    finish(socket, result, "Approval #{decision}.")
  end

  def handle_event(
        "publish",
        %{"candidate_id" => id, "approval_id" => approval_id} = params,
        socket
      ) do
    options = [skill: params["skill"] == "true"]
    finish(socket, Knowledge.publish(id, approval_id, @actor, options), "Knowledge published.")
  end

  def handle_event("request-revocation", %{"publication_id" => id}, socket) do
    finish(socket, Knowledge.request_revocation(id), "Revocation approval requested.")
  end

  def handle_event(
        "request-rollback",
        %{"publication_id" => id, "target_version" => version},
        socket
      ) do
    case Integer.parse(version) do
      {version, ""} ->
        finish(socket, Knowledge.request_rollback(id, version), "Rollback approval requested.")

      _other ->
        finish(socket, {:error, :invalid_rollback_version}, "")
    end
  end

  def handle_event(
        "apply-approved",
        %{"approval_id" => approval_id, "kind" => kind},
        socket
      ) do
    finish(
      socket,
      apply_approved(socket.assigns.publications, approval_id, kind),
      "Approval applied."
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app>
      <section aria-labelledby="knowledge-review-heading" class="space-y-8">
        <header class="space-y-2">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">
            Project knowledge
          </p>
          <h1
            id="knowledge-review-heading"
            class="text-3xl font-semibold tracking-tight text-slate-950"
          >
            Review queue
          </h1>
          <p class="max-w-3xl text-slate-700">
            Inspect redacted evidence, accept or reject project knowledge, and apply separately approved global changes.
          </p>
        </header>

        <p role="status" aria-live="polite" class="min-h-6 text-sm text-emerald-900">
          {@notice}
        </p>
        <p
          :if={@error != ""}
          role="alert"
          class="rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-950"
        >
          {@error}
        </p>

        <section aria-labelledby="candidates-heading" class="space-y-4">
          <h2 id="candidates-heading" class="text-xl font-semibold text-slate-950">
            Candidates
          </h2>
          <p :if={@candidates == []} class="rounded-md border border-slate-300 p-5 text-slate-700">
            No knowledge candidates have been extracted.
          </p>
          <ol :if={@candidates != []} class="space-y-4">
            <li :for={candidate <- @candidates}>
              <article
                id={"candidate-#{candidate.id}"}
                aria-labelledby={"candidate-title-#{candidate.id}"}
                class="space-y-4 rounded-lg border border-slate-300 bg-white p-5"
              >
                <header class="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p class="text-sm font-medium text-slate-600">
                      {candidate.kind} · {candidate.operation}
                    </p>
                    <h3
                      id={"candidate-title-#{candidate.id}"}
                      class="text-lg font-semibold text-slate-950"
                    >
                      {candidate.title}
                    </h3>
                  </div>
                  <span class="rounded-full border border-slate-300 px-3 py-1 text-sm text-slate-800">
                    {candidate.decision}
                  </span>
                </header>

                <div class="prose prose-slate max-w-none whitespace-pre-wrap text-sm">
                  {candidate.content}
                </div>

                <details class="rounded-md border border-slate-200 p-3">
                  <summary class="cursor-pointer font-medium text-slate-900 focus-visible:outline-2 focus-visible:outline-offset-2">
                    Evidence and redaction
                  </summary>
                  <dl class="mt-3 grid gap-2 text-sm sm:grid-cols-2">
                    <div>
                      <dt class="font-medium text-slate-700">Run</dt>
                      <dd class="break-all text-slate-900">{candidate.evidence_json["run_id"]}</dd>
                    </div>
                    <div>
                      <dt class="font-medium text-slate-700">Redaction</dt>
                      <dd class="text-slate-900">{candidate.redaction_state}</dd>
                    </div>
                    <div class="sm:col-span-2">
                      <dt class="font-medium text-slate-700">Evidence events</dt>
                      <dd class="break-words text-slate-900">
                        {Enum.join(candidate.evidence_json["event_ids"] || [], ", ")}
                      </dd>
                    </div>
                  </dl>
                </details>

                <form
                  :if={candidate.decision == "pending"}
                  phx-submit="review"
                  class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto_auto]"
                >
                  <input type="hidden" name="candidate_id" value={candidate.id} />
                  <label class="grid gap-1 font-medium text-slate-800">
                    Review reason
                    <input
                      name="reason"
                      required
                      maxlength="500"
                      class="min-h-10 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
                    />
                  </label>
                  <label class="grid gap-1 font-medium text-slate-800">
                    Decision
                    <select
                      name="decision"
                      class="min-h-10 rounded-md border border-slate-400 bg-white px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
                    >
                      <option value="accepted">Accept project item</option>
                      <option value="rejected">Reject</option>
                    </select>
                  </label>
                  <button class="min-h-10 self-end rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2">
                    Save review
                  </button>
                </form>

                <div :if={candidate.decision == "accepted"} class="flex flex-wrap gap-3">
                  <form
                    :if={is_nil(publication_approval(candidate, @approvals))}
                    phx-submit="request-publication"
                  >
                    <input type="hidden" name="candidate_id" value={candidate.id} />
                    <button class="min-h-10 rounded-md border border-slate-400 bg-white px-4 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2">
                      Request global approval
                    </button>
                  </form>

                  <form
                    :if={publishable_approval(candidate, @approvals, @publications)}
                    phx-submit="publish"
                    class="flex flex-wrap items-end gap-3"
                  >
                    <input type="hidden" name="candidate_id" value={candidate.id} />
                    <input
                      type="hidden"
                      name="approval_id"
                      value={publishable_approval(candidate, @approvals, @publications).id}
                    />
                    <label
                      :if={candidate.kind == "recipe"}
                      class="flex min-h-10 items-center gap-2 font-medium text-slate-800"
                    >
                      <input type="checkbox" name="skill" value="true" /> Package as skill
                    </label>
                    <button class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2">
                      Publish globally
                    </button>
                  </form>
                </div>
              </article>
            </li>
          </ol>
        </section>

        <section aria-labelledby="approvals-heading" class="space-y-4">
          <h2 id="approvals-heading" class="text-xl font-semibold text-slate-950">
            Knowledge approvals
          </h2>
          <p :if={@approvals == []} class="text-sm text-slate-700">No knowledge approvals.</p>
          <ul class="space-y-3">
            <li :for={approval <- @approvals} class="rounded-md border border-slate-300 p-4">
              <p class="break-all font-medium text-slate-950">{approval.kind}</p>
              <p class="text-sm text-slate-700">Decision: {approval.decision}</p>
              <form
                :if={approval.decision == "pending"}
                phx-submit="decide-approval"
                class="mt-3 grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto_auto]"
              >
                <input type="hidden" name="approval_id" value={approval.id} />
                <label class="grid gap-1 font-medium text-slate-800">
                  Decision reason
                  <input
                    name="reason"
                    required
                    maxlength="500"
                    class="min-h-10 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
                  />
                </label>
                <label class="grid gap-1 font-medium text-slate-800">
                  Decision
                  <select
                    name="decision"
                    class="min-h-10 rounded-md border border-slate-400 bg-white px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
                  >
                    <option value="approved">Approve</option>
                    <option value="rejected">Reject</option>
                  </select>
                </label>
                <button class="min-h-10 self-end rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2">
                  Save decision
                </button>
              </form>
              <form
                :if={actionable_approval?(approval, @publications)}
                phx-submit="apply-approved"
                class="mt-3"
              >
                <input type="hidden" name="approval_id" value={approval.id} />
                <input type="hidden" name="kind" value={approval.kind} />
                <button class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2">
                  Apply approved change
                </button>
              </form>
            </li>
          </ul>
        </section>

        <section aria-labelledby="publication-history-heading" class="space-y-4">
          <h2 id="publication-history-heading" class="text-xl font-semibold text-slate-950">
            Publication history
          </h2>
          <p :if={@publications == []} class="text-sm text-slate-700">Nothing published globally.</p>
          <div :if={@publications != []} class="overflow-x-auto">
            <table class="min-w-full border-collapse text-left text-sm">
              <caption class="sr-only">Global knowledge publication versions</caption>
              <thead>
                <tr class="border-b border-slate-300">
                  <th scope="col" class="p-3">Version</th>
                  <th scope="col" class="p-3">Action</th>
                  <th scope="col" class="p-3">Hash</th>
                  <th scope="col" class="p-3">Controls</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={publication <- @publications} class="border-b border-slate-200">
                  <td class="p-3">v{publication.version}</td>
                  <td class="p-3">{publication.action}</td>
                  <td class="max-w-48 truncate p-3 font-mono" title={publication.content_hash}>
                    {publication.content_hash}
                  </td>
                  <td class="p-3">
                    <div :if={latest?(publication, @publications)} class="flex flex-wrap gap-2">
                      <form phx-submit="request-revocation">
                        <input type="hidden" name="publication_id" value={publication.id} />
                        <button class="min-h-10 rounded-md border border-slate-400 bg-white px-3 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2">
                          Request revocation
                        </button>
                      </form>
                      <form
                        :if={publication.version > 1}
                        phx-submit="request-rollback"
                        class="flex gap-2"
                      >
                        <input type="hidden" name="publication_id" value={publication.id} />
                        <label class="grid gap-1 font-medium text-slate-800">
                          Roll back to version
                          <input
                            name="target_version"
                            type="number"
                            min="1"
                            max={publication.version - 1}
                            value="1"
                            required
                            class="min-h-10 w-24 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
                          />
                        </label>
                        <button class="min-h-10 self-end rounded-md border border-slate-400 bg-white px-3 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2">
                          Request rollback
                        </button>
                      </form>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  defp load(socket) do
    assign(socket,
      candidates: Knowledge.list_candidates(),
      approvals: Knowledge.list_knowledge_approvals(),
      publications: Knowledge.list_publications()
    )
  end

  defp finish(socket, {:ok, _value}, notice) do
    {:noreply, socket |> assign(notice: notice, error: "") |> load()}
  end

  defp finish(socket, {:error, reason}, _notice) do
    {:noreply, assign(socket, notice: "", error: humanize(reason))}
  end

  defp publication_approval(candidate, approvals) do
    Enum.find(approvals, &(&1.kind == "knowledge_publication:#{candidate.id}"))
  end

  defp publishable_approval(candidate, approvals, publications) do
    approval = publication_approval(candidate, approvals)

    published? =
      Enum.any?(publications, &(&1.candidate_id == candidate.id and &1.action == "publish"))

    if approval && approval.decision == "approved" && not published?, do: approval
  end

  defp latest?(publication, publications) do
    publication.version ==
      publications
      |> Enum.filter(&(&1.knowledge_item_id == publication.knowledge_item_id))
      |> Enum.map(& &1.version)
      |> Enum.max(fn -> 0 end)
  end

  defp actionable_approval?(approval, publications) do
    approval.decision == "approved" and
      String.starts_with?(approval.kind, ["knowledge_revocation:", "knowledge_rollback:"]) and
      not Enum.any?(publications, &(&1.approval_id == approval.id))
  end

  defp apply_approved(publications, approval_id, "knowledge_revocation:" <> item_id) do
    case latest_for_item(publications, item_id) do
      nil -> {:error, :publication_not_found}
      publication -> Knowledge.revoke(publication.id, approval_id, @actor)
    end
  end

  defp apply_approved(publications, approval_id, "knowledge_rollback:" <> value) do
    with [item_id, version] <- String.split(value, ":"),
         {version, ""} <- Integer.parse(version),
         %{} = publication <- latest_for_item(publications, item_id) do
      Knowledge.rollback(publication.id, version, approval_id, @actor)
    else
      _other -> {:error, :invalid_rollback_approval}
    end
  end

  defp apply_approved(_publications, _approval_id, _kind),
    do: {:error, :unsupported_knowledge_approval}

  defp latest_for_item(publications, item_id) do
    publications
    |> Enum.filter(&(&1.knowledge_item_id == item_id))
    |> Enum.max_by(& &1.version, fn -> nil end)
  end

  defp humanize(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp humanize(_reason), do: "The knowledge command failed."
end
