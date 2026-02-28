# SPDX-FileCopyrightText: 2022 ash_paper_trail contributors <https://github.com/ash-project/ash_paper_trail/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPaperTrail.ChangeBuilders.Snapshot do
  @moduledoc false
  def build_changes(attributes, changeset, result) do
    Enum.reduce(attributes, %{}, &build_attribute_change(&1, changeset, result, &2))
  end

  def build_attribute_change(attribute, _changeset, result, changes) do
    dumped_value = case Map.get(result, attribute.name) do
      nil ->
        nil

      %Ash.NotLoaded{} ->
        nil

      %Ash.ForbiddenField{} ->
        nil

      value ->
        {:ok, dumped_value} = Ash.Type.dump_to_embedded(attribute.type, value, attribute.constraints)
        dumped_value
    end

    Map.put(changes, attribute.name, dumped_value)
  end
end
