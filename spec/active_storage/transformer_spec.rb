# frozen_string_literal: true

RSpec.describe ActiveStorage::AsyncVariants::Transformer do
  # A transformer's kind is derived from what it overrides; naming any of them
  # on a variant is the async opt-in.
  describe "kind predicates" do
    it "classifies the built-in Standard (overrides neither) as standard" do
      t = ActiveStorage::AsyncVariants::Standard.new
      expect(t.standard?).to be true
      expect(t.inline?).to be false
      expect(t.external?).to be false
    end

    it "classifies a #process override as inline" do
      klass = Class.new(described_class) { def process(file, **o); end }
      t = klass.new
      expect(t.inline?).to be true
      expect(t.external?).to be false
      expect(t.standard?).to be false
    end

    it "classifies an #initiate override as external" do
      klass = Class.new(described_class) { def initiate(source_url:, callback_url:, **o); end }
      t = klass.new
      expect(t.external?).to be true
      expect(t.inline?).to be false
      expect(t.standard?).to be false
    end

    it "treats the bare base class as standard" do
      expect(described_class.new.standard?).to be true
    end
  end
end
