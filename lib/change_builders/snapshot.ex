# SPDX-FileCopyrightText: 2022 ash_paper_trail contributors <https://github.com/ash-project/ash_paper_trail/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPaperTrail.ChangeBuilders.Snapshot do
  @moduledoc false
  import AshPaperTrail.ChangeBuilders.Helpers

  def build_changes(attributes, changeset, result) do
    Enum.reduce(attributes, %{}, &build_attribute_change(&1, changeset, result, &2))
  end

  def build_attribute_change(attribute, _changeset, result, changes) do
    value = Map.get(result, attribute.name)

    if capturable_value?(value) do
      Map.put(changes, attribute.name, dump_value(value, attribute))
    else
      # The value is unknown (not loaded or forbidden), so the key is omitted
      # rather than recording a false nil.
      changes
    end
  end
end
