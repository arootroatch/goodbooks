require "rails_helper"

RSpec.describe AppHost do
  it "returns APP_HOST when set" do
    expect(AppHost.fetch!("APP_HOST" => "books.example.com")).to eq("books.example.com")
  end

  it "refuses to boot when APP_HOST is blank" do
    expect { AppHost.fetch!("APP_HOST" => "") }.to raise_error(/APP_HOST/)
    expect { AppHost.fetch!({}) }.to raise_error(/APP_HOST/)
    expect { AppHost.fetch!("SECRET_KEY_BASE_DUMMY" => "") }.to raise_error(/APP_HOST/)
  end

  it "lets the image build precompile assets without APP_HOST" do
    expect(AppHost.fetch!("SECRET_KEY_BASE_DUMMY" => "1")).to eq("localhost")
  end

  it "serves HTTPS everywhere but localhost, where first-run setup happens without a tunnel" do
    expect(AppHost.https?("books.example.com")).to be(true)
    expect(AppHost.https?("localhost")).to be(false)
  end
end
