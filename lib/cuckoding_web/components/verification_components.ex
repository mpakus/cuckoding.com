defmodule CuckodingWeb.VerificationComponents do
  @moduledoc "Planned check display and inputs inside existing task dialogs."
  use CuckodingWeb, :html
  alias Cuckoding.TaskChecks
  alias Phoenix.LiveView.JS

  attr :entries, :list, default: []

  def verification(assigns) do
    ~H"""
    <ul :if={@entries != []} class="fine-print">
      <li :for={row <- @entries}>
        {TaskChecks.label(row["profile"])} · <code>{row["directory"]}</code>
        · {row["timeout_seconds"]}s
      </li>
    </ul>
    """
  end

  attr :content, :map, required: true
  attr :form_key, :string, required: true

  def verification_editor(assigns) do
    assigns = assign(assigns, :entries, assigns.content["verification"] || [])

    ~H"""
    <details id="draft-verification" phx-mounted={JS.ignore_attributes("open")}>
      <summary id="draft-verification-heading">
        Verification · {length(@entries)}
      </summary>
      <p id="draft-verification-help" class="fine-print">
        The agent proposes these with the task. Start runs them offline in Linux;
        no project dependencies are downloaded. Other verification stays in the criteria.
      </p>
      <input
        :if={Map.has_key?(@content, "verification")}
        type="hidden"
        name="verification_present"
        value="true"
      />
      <fieldset
        :for={{row, index} <- Enum.with_index(@entries)}
        class="role-fields"
        aria-describedby="draft-verification-help"
      >
        <legend>Check {index + 1}</legend>
        <label for={"verification-profile-#{index}"}>Check</label>
        <select id={"verification-profile-#{index}"} name={"verification[#{index}][profile]"}>
          <option value="" selected={row["profile"] == ""}>Choose a check</option>
          <option
            :for={profile <- TaskChecks.profiles()}
            value={profile}
            selected={profile == row["profile"]}
          >
            {TaskChecks.label(profile)}
          </option>
        </select>
        <label for={"verification-directory-#{index}"}>Folder relative to the Arena</label>
        <input
          id={"verification-directory-#{index}"}
          type="text"
          name={"verification[#{index}][directory]"}
          value={row["directory"]}
          maxlength="240"
          required
        />
        <label for={"verification-timeout-#{index}"}>Time limit in seconds</label>
        <input
          id={"verification-timeout-#{index}"}
          type="number"
          name={"verification[#{index}][timeout_seconds]"}
          value={row["timeout_seconds"]}
          min="1"
          max="300"
          required
        />
        <button
          type="button"
          class="button secondary"
          aria-label={"Remove check #{index + 1}"}
          phx-click={
            JS.push("verification-remove", value: %{key: @form_key, index: index})
            |> JS.focus(to: "#draft-verification-heading")
          }
        >
          Remove
        </button>
      </fieldset>
      <button
        id="draft-verification-add"
        type="button"
        class="button secondary"
        disabled={length(@entries) >= 4}
        phx-click={
          JS.push("verification-add", value: %{key: @form_key})
          |> JS.focus(to: "#draft-verification-heading")
        }
      >
        Add check
      </button>
      <p class="fine-print" role="status">
        Up to four checks per task. Start freezes the saved task and permitted checks.
      </p>
    </details>
    """
  end
end
