# SPDX-FileCopyrightText: 2022 ash_paper_trail contributors <https://github.com/ash-project/ash_paper_trail/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPaperTrail.ChangeBuilders.Helpers do
  @moduledoc """
  Helpers shared by all change tracking modes.
  """

  @doc """
  Whether a value read from an action result carries a value we can record.

  `%Ash.NotLoaded{}` (e.g. from a narrow `select`) and `%Ash.ForbiddenField{}`
  (from field policies) mean the value is unknown, not that it is nil.
  """
  def capturable_value?(%Ash.NotLoaded{}), do: false
  def capturable_value?(%Ash.ForbiddenField{}), do: false
  def capturable_value?(_value), do: true

  @doc """
  Dumps an attribute value to an embeddable representation.
  """
  def dump_value(nil, _attribute), do: nil

  def dump_value(values, %{type: {:array, attr_type}} = attribute) do
    item_constraints = attribute.constraints[:items]

    # This is a work around for a bug in Ash.Type.dump_to_embedded/3
    Enum.map(values, fn value ->
      {:ok, dumped_value} = Ash.Type.dump_to_embedded(attr_type, value, item_constraints)
      dumped_value
    end)
  end

  def dump_value(value, attribute) do
    {:ok, dumped_value} = Ash.Type.dump_to_embedded(attribute.type, value, attribute.constraints)
    dumped_value
  end
end
