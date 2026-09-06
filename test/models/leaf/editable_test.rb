require "test_helper"

class Leaf::EditableTest < ActiveSupport::TestCase
  test "editing a leafable records the edit" do
    leaves(:welcome_page).edit leafable_params: { body: "New body" }

    assert_equal "New body", leaves(:welcome_page).page.body.content

    assert leaves(:welcome_page).edits.last.revision?
    assert_equal "This is _such_ a great handbook.", leaves(:welcome_page).edits.last.page.body.content
  end

  test "edits that are close together don't create new revisions" do
    assert_difference -> { leaves(:welcome_page).edits.count }, +1 do
      leaves(:welcome_page).edit leafable_params: { body: "First change" }
    end

    freeze_time
    travel 1.minute

    assert_no_difference -> { leaves(:welcome_page).edits.count } do
      leaves(:welcome_page).edit leafable_params: { body: "Second change" }
    end

    assert_equal "Second change", leaves(:welcome_page).page.body.content
    assert_equal Time.now, leaves(:welcome_page).edits.last.updated_at

    travel 1.hour

    assert_difference -> { leaves(:welcome_page).edits.count }, +1 do
      leaves(:welcome_page).edit leafable_params: { body: "Third change" }
    end
  end

  test "changing a leaf title doesn't create a revision" do
    assert_no_difference -> { Edit.count } do
      leaves(:welcome_page).edit leaf_params: { title: "New title" }
    end

    assert_equal "New title", leaves(:welcome_page).title
  end

  test "changes that don't affect the leafable don't create a revision" do
    assert_no_difference -> { Edit.count } do
      leaves(:welcome_page).edit leafable_params: {}
    end
  end

  test "re-sending an identical body doesn't create a revision" do
    leaves(:welcome_page).edit leafable_params: { body: "New body" }

    travel 1.hour do
      assert_no_difference -> { Edit.count } do
        leaves(:welcome_page).edit leafable_params: { body: "New body" }
      end
    end
  end

  test "re-sending an identical section body doesn't create a revision" do
    leaves(:welcome_section).edit leafable_params: { body: "New body" }

    travel 1.hour do
      assert_no_difference -> { Edit.count } do
        leaves(:welcome_section).edit leafable_params: { body: "New body" }
      end
    end
  end

  test "editing a leafable with an attachment includes the attachments in the new version" do
    assert leaves(:reading_picture).picture.image.attached?

    leaves(:reading_picture).edit leaf_params: { title: "New title" }

    assert_equal "New title", leaves(:reading_picture).title
    assert leaves(:reading_picture).picture.image.attached?
  end

  test "trashing a leaf records the edit" do
    leaves(:welcome_page).trashed!

    assert leaves(:welcome_page).trashed?

    assert leaves(:welcome_page).edits.last.trash?
    assert_equal "This is _such_ a great handbook.", leaves(:welcome_page).edits.last.page.body.content
  end
end
