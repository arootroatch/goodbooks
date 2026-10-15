require "rails_helper"

RSpec.describe EncryptionKeys do
  let(:env) do
    { "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "p", "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "d",
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => "s" }
  end

  it "reads the keys from the environment" do
    expect(EncryptionKeys.fetch!(env, {})).to eq(primary_key: "p", deterministic_key: "d", key_derivation_salt: "s")
  end

  it "falls back to credentials for keys the environment leaves blank" do
    credentials = { active_record_encryption: { primary_key: "cp", deterministic_key: "cd", key_derivation_salt: "cs" } }
    keys = EncryptionKeys.fetch!(env.merge("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => ""), credentials)
    expect(keys).to eq(primary_key: "cp", deterministic_key: "d", key_derivation_salt: "s")
  end

  it "refuses to boot without every key, naming the missing ones" do
    expect { EncryptionKeys.fetch!(env.except("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"), {}) }
      .to raise_error(/ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT/)
    expect { EncryptionKeys.fetch!({}, {}) }.to raise_error(/ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY.*README/m)
  end

  it "lets the image build precompile assets without keys" do
    expect(EncryptionKeys.fetch!({ "SECRET_KEY_BASE_DUMMY" => "1" }, {})).to eq({})
  end
end
