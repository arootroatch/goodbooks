# Creates the household's single personal book and keeps its memberships in step with the household:
# household owners are owners, users linked to a Person are editors. The accountant never gets one.
class PersonalBookProvisioner
  NAME = "Personal"

  def self.call(household)
    household.with_lock do
      book = household.personal_book || household.businesses.create!(kind: "personal", name: NAME).tap { CategoryTemplate.apply_to(_1) }
      sync_memberships(book)
      book
    end
  end

  def self.sync(household)
    book = household.personal_book
    sync_memberships(book) if book
  end

  def self.sync_memberships(book)
    User.where(household_owner: true).find_each { grant(book, _1, "owner") }
    User.where(household_owner: false, id: book.household.people.select(:user_id)).find_each { grant(book, _1, "editor") }
  end

  def self.grant(book, user, role)
    book.memberships.find_or_create_by!(user: user) { _1.role = role }
  end

  private_class_method :sync_memberships, :grant
end
