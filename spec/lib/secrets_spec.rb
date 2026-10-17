require "rails_helper"

RSpec.describe Secrets do
  describe ".secret_key_base!" do
    it "reads SECRET_KEY_BASE" do
      expect(Secrets.secret_key_base!({ "SECRET_KEY_BASE" => "env" })).to eq("env")
    end

    it "refuses to boot without one, counting blank as unset" do
      expect { Secrets.secret_key_base!({ "SECRET_KEY_BASE" => "" }) }.to raise_error("SECRET_KEY_BASE not set. Set it in .env (see README).")
      expect { Secrets.secret_key_base!({}) }.to raise_error(/SECRET_KEY_BASE not set/)
    end

    it "lets the image build precompile assets without one" do
      expect(Secrets.secret_key_base!({ "SECRET_KEY_BASE_DUMMY" => "1" })).to be_nil
    end
  end

  describe ".encryption_keys!" do
    let(:env) do
      { "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "p", "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "d",
        "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => "s" }
    end

    it "reads the keys from the environment" do
      expect(Secrets.encryption_keys!(env)).to eq(primary_key: "p", deterministic_key: "d", key_derivation_salt: "s")
    end

    it "refuses to boot without every key, naming the missing ones" do
      expect { Secrets.encryption_keys!(env.except("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")) }
        .to raise_error("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT not set. Set it in .env (see README).")
      expect { Secrets.encryption_keys!(env.merge("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "")) }
        .to raise_error("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY not set. Set it in .env (see README).")
      expect { Secrets.encryption_keys!({}) }.to raise_error(/PRIMARY_KEY, .*DETERMINISTIC_KEY, .*SALT not set. Set them/)
    end

    it "lets the image build precompile assets without keys" do
      expect(Secrets.encryption_keys!({ "SECRET_KEY_BASE_DUMMY" => "1" })).to eq({})
    end
  end
end
