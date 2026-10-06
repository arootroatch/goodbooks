require "rails_helper"

RSpec.describe MoneyAttribute do
  let(:model_class) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes
      include ActiveModel::Validations
      attribute :amount_cents, :integer
      attribute :limit_cents, :integer
      include MoneyAttribute
      money_attribute :amount
      money_attribute :limit, allow_blank: true

      def self.name = "Thing"

      def [](key) = public_send(key)
      def []=(key, value)
        public_send("#{key}=", value)
      end
    end
  end

  it "parses input into cents" do
    thing = model_class.new(amount: "$1,234.50")
    expect(thing.amount_cents).to eq(123450)
    expect(thing).to be_valid
  end

  it "keeps the raw input for redisplay and reports the parse error" do
    thing = model_class.new(amount: "abc")
    expect(thing.amount).to eq("abc")
    expect(thing.amount_cents).to be_nil
    expect(thing).not_to be_valid
    expect(thing.errors[:amount]).to include("is not a valid amount")
  end

  it "formats stored cents for forms when no input was given" do
    thing = model_class.new(amount_cents: -500)
    expect(thing.amount).to eq("-5.00")
  end

  it "allows blank when configured" do
    thing = model_class.new(amount: "1", limit: "")
    expect(thing.limit_cents).to be_nil
    expect(thing).to be_valid
  end

  it "rejects blank when not configured" do
    thing = model_class.new(amount: "")
    expect(thing).not_to be_valid
    expect(thing.errors[:amount]).to include("can't be blank")
  end

  it "rejects when omitted and not configured for blank" do
    thing = model_class.new(limit: "")
    expect(thing).not_to be_valid
    expect(thing.errors[:amount]).to include("can't be blank")
  end
end
