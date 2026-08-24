# SPDX-FileCopyrightText: 2022 ash_paper_trail contributors <https://github.com/ash-project/ash_paper_trail/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPaperTrail.NotLoadedFieldsTest do
  @moduledoc """
  Values in an action result can be `%Ash.NotLoaded{}` (narrow `select`) or
  `%Ash.ForbiddenField{}` (field policies). Versions must be created without
  crashing, and unknown values must be omitted rather than recorded as nil.
  """
  use ExUnit.Case

  require Ash.Query

  alias AshPaperTrail.ChangeBuilders
  alias AshPaperTrail.Test.Posts

  @not_loaded %Ash.NotLoaded{type: :attribute, field: :body}
  @forbidden %Ash.ForbiddenField{field: :body, type: :attribute}

  describe "ChangeBuilders.Helpers" do
    test "capturable_value?/1" do
      refute ChangeBuilders.Helpers.capturable_value?(@not_loaded)
      refute ChangeBuilders.Helpers.capturable_value?(@forbidden)
      assert ChangeBuilders.Helpers.capturable_value?(nil)
      assert ChangeBuilders.Helpers.capturable_value?("value")
    end

    test "dump_value/2 dumps nil and real values" do
      attribute = Ash.Resource.Info.attribute(Posts.SnapshotPost, :body)

      assert ChangeBuilders.Helpers.dump_value(nil, attribute) == nil
      assert ChangeBuilders.Helpers.dump_value("body", attribute) == "body"
      assert ChangeBuilders.FullDiff.Helpers.dump_value("body", attribute) == "body"
    end
  end

  describe "FullDiff.Helpers.get_data/2" do
    test "records not loaded and forbidden data as nil" do
      post = Posts.SnapshotPost.create!(%{subject: "subject", body: "body"})
      attribute = Ash.Resource.Info.attribute(Posts.SnapshotPost, :body)

      changeset = Ash.Changeset.for_update(post, :update, %{})
      assert ChangeBuilders.FullDiff.Helpers.get_data(changeset, attribute) == "body"

      not_loaded =
        Ash.Changeset.for_update(%{post | body: @not_loaded}, :update, %{})

      assert ChangeBuilders.FullDiff.Helpers.get_data(not_loaded, attribute) == nil

      forbidden =
        Ash.Changeset.for_update(%{post | body: @forbidden}, :update, %{})

      assert ChangeBuilders.FullDiff.Helpers.get_data(forbidden, attribute) == nil
    end
  end

  describe "Snapshot.build_attribute_change/4" do
    test "omits not loaded and forbidden values instead of recording nil" do
      post = Posts.SnapshotPost.create!(%{subject: "subject", body: "body"})
      attribute = Ash.Resource.Info.attribute(Posts.SnapshotPost, :body)

      assert ChangeBuilders.Snapshot.build_attribute_change(
               attribute,
               nil,
               %{post | body: @not_loaded},
               %{}
             ) == %{}

      assert ChangeBuilders.Snapshot.build_attribute_change(
               attribute,
               nil,
               %{post | body: @forbidden},
               %{}
             ) == %{}
    end

    test "still records genuine nil and real values" do
      post = Posts.SnapshotPost.create!(%{subject: "subject", body: "body"})
      attribute = Ash.Resource.Info.attribute(Posts.SnapshotPost, :body)

      assert ChangeBuilders.Snapshot.build_attribute_change(
               attribute,
               nil,
               %{post | body: nil},
               %{}
             ) == %{body: nil}

      assert ChangeBuilders.Snapshot.build_attribute_change(attribute, nil, post, %{}) ==
               %{body: "body"}
    end
  end

  describe "ChangesOnly.build_attribute_change/4" do
    test "omits a changing attribute whose result value is not loaded or forbidden" do
      post = Posts.SnapshotPost.create!(%{subject: "subject", body: "body"})
      changeset = Ash.Changeset.for_update(post, :update, %{body: "new body"})
      attribute = Ash.Resource.Info.attribute(Posts.SnapshotPost, :body)

      assert Ash.Changeset.changing_attribute?(changeset, :body)

      assert ChangeBuilders.ChangesOnly.build_attribute_change(
               attribute,
               changeset,
               %{post | body: @not_loaded},
               %{}
             ) == %{}

      assert ChangeBuilders.ChangesOnly.build_attribute_change(
               attribute,
               changeset,
               %{post | body: @forbidden},
               %{}
             ) == %{}
    end

    test "still records a changing attribute with a loaded value" do
      post = Posts.SnapshotPost.create!(%{subject: "subject", body: "body"})
      changeset = Ash.Changeset.for_update(post, :update, %{body: "new body"})
      attribute = Ash.Resource.Info.attribute(Posts.SnapshotPost, :body)

      assert ChangeBuilders.ChangesOnly.build_attribute_change(
               attribute,
               changeset,
               %{post | body: "new body"},
               %{}
             ) == %{body: "new body"}
    end
  end

  describe ":snapshot mode with a narrowly selected record" do
    test "destroying a record read with a narrow select creates a version that omits unknown fields" do
      post = Posts.SnapshotPost.create!(%{subject: "subject", body: "body", views: 7})

      narrow =
        Posts.SnapshotPost
        |> Ash.Query.filter(id == ^post.id)
        |> Ash.Query.select([:id, :subject])
        |> Ash.read_one!()

      assert %Ash.NotLoaded{} = narrow.body

      assert :ok = Posts.SnapshotPost.destroy!(narrow)

      [destroy_version] =
        Ash.read!(Posts.SnapshotPost.Version)
        |> Enum.filter(&(&1.version_action_type == :destroy))

      # loaded attributes are recorded; unknown ones are omitted, not nil
      assert destroy_version.changes == %{subject: "subject"}
      refute Map.has_key?(destroy_version.changes, :body)
      refute Map.has_key?(destroy_version.changes, :views)

      # attributes_as_attributes: the loaded attribute is copied, the
      # not loaded one is skipped instead of failing to cast
      assert destroy_version.subject == "subject"
      assert destroy_version.body == nil
    end

    test "a fully loaded update still snapshots every attribute" do
      post = Posts.SnapshotPost.create!(%{subject: "subject", body: "body"})
      Posts.SnapshotPost.update!(post, %{subject: "new subject"})

      [update_version] =
        Ash.read!(Posts.SnapshotPost.Version)
        |> Enum.filter(&(&1.version_action_type == :update))

      assert [:body, :subject, :views] = Map.keys(update_version.changes) |> Enum.sort()
    end
  end

  describe ":full_diff mode with a narrowly selected record" do
    test "destroying a record read with a narrow select creates a version" do
      # this test shares FullDiffPost's ets tables with full_diff_test.exs, so
      # wipe them afterwards to keep the versions it creates out of other tests
      on_exit(fn ->
        Ash.DataLayer.Ets.stop(Posts.FullDiffPost)
        Ash.DataLayer.Ets.stop(Posts.FullDiffPost.Version)
      end)

      post =
        Posts.FullDiffPost.create!(%{
          subject: "subject",
          body: "body",
          author: %{first_name: "John", last_name: "Doe"},
          tags: [%{tag: "ash"}],
          lucky_numbers: [7],
          moderator_reaction: 100
        })

      narrow =
        Posts.FullDiffPost
        |> Ash.Query.filter(id == ^post.id)
        |> Ash.Query.select([:id, :subject])
        |> Ash.read_one!()

      assert %Ash.NotLoaded{} = narrow.body

      assert :ok = Posts.FullDiffPost.destroy!(narrow)

      [destroy_version] =
        Ash.read!(Posts.FullDiffPost.Version)
        |> Enum.filter(&(&1.version_action_type == :destroy and &1.version_source_id == post.id))

      # the loaded simple attribute keeps its diff, unknown ones diff as nil
      assert destroy_version.changes[:subject] == %{unchanged: "subject"}
      assert destroy_version.changes[:body] == %{unchanged: nil}

      # attributes_as_attributes skips the not loaded values
      assert destroy_version.subject == "subject"
      assert destroy_version.body == nil
    end
  end
end
