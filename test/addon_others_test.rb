#! /usr/bin/env rspec

require_relative "./test_helper"
Yast.import "AddOnOthers"

describe Yast::AddOnOthers do
  subject { Yast::AddOnOthers }

  let(:available_products) do
    [Y2Packager::Resolvable.new(kind: :product,
      name: "SLE_RT", status: :available, source: 2),
     Y2Packager::Resolvable.new(kind: :product,
       name: "SLE_HPC", status: :available, source: 2),
     Y2Packager::Resolvable.new(kind: :product,
       name: "SLE_SAP", status: :available, source: 2),
     Y2Packager::Resolvable.new(kind: :product,
       name: "SLE_BCL", status: :available, source: 2),
     Y2Packager::Resolvable.new(kind: :product,
       name: "SLED", status: :available, source: 2),
     Y2Packager::Resolvable.new(kind: :product,
       name: "SUSE-Manager-Server", status: :available, source: 2),
     Y2Packager::Resolvable.new(kind: :product,
       name: "SUSE-Manager-Proxy", status: :available, source: 2),
     Y2Packager::Resolvable.new(kind: :product,
       name: "sle-module-desktop-applications", status: :available, source: 1),
     Y2Packager::Resolvable.new(kind: :product,
       name: "sle-module-basesystem", status: :available, source: 0),
     Y2Packager::Resolvable.new(kind: :product,
       name: "SLES", status: :available, source: 3),
     Y2Packager::Resolvable.new(kind: :product,
       name: "SLES", status: :available, source: 2),
     Y2Packager::Resolvable.new(kind: :product,
       name: "SUSE-Manager-Retail-Branch-Server", status: :available, source: 2)]
  end

  let(:installed_products) do
    [Y2Packager::Resolvable.new(kind: :product,
      name: "sle-module-desktop-applications", status: :installed, source: -1),
     Y2Packager::Resolvable.new(kind: :product,
       name: "sle-module-basesystem", status: :installed, source: -1),
     Y2Packager::Resolvable.new(kind: :product,
       name: "SLES", status: :installed, source: -1)]
  end

  let(:repo_hash) do
    { "alias"       => "user defined",
      "url"         => "http://xxx.url?foo=bar",
      "name"        => "user_defined",
      "priority"    => 19,
      "product_dir" => "/" }
  end

  before do
    allow(Y2Packager::Resolvable).to receive(:find).with(kind: :product, status: :available)
      .and_return(available_products)
    allow(Y2Packager::Resolvable).to receive(:find).with(kind: :product, status: :installed)
      .and_return(installed_products)
    allow(Yast::Pkg).to receive(:SourceGetCurrent).with(true)
      .and_return([0, 1, 2, 3, 4])
    allow(subject).to receive(:require).with("registration/registration")
      .and_raise(LoadError)
  end

  describe "#Read" do

    context "installed products and add-ons are available" do

      it "returns user defined repo only" do
        expect(Yast::Pkg).to receive(:SourceGeneralData).with(4)
          .and_return(repo_hash)
        expect(Yast::AddOnOthers.Read).to eq([repo_hash])
      end
    end
  end

  describe "#Export" do
    context "installed products and add-ons are available" do
      let(:ret) do
        { "media_url"   => repo_hash["url"],
          "alias"       => repo_hash["alias"],
          "priority"    => repo_hash["priority"],
          "name"        => repo_hash["name"],
          "product_dir" => repo_hash["product_dir"] }
      end

      before do
        allow(Yast::Pkg).to receive(:SourceGeneralData).with(4)
          .and_return(repo_hash)
      end

      it "returns an array of user defined repos in AY format" do
        Yast::AddOnOthers.Read()
        expect(Yast::AddOnOthers.Export).to eq("add_on_others" => [ret])
      end

      context "when an add-on is registered" do
        let(:registration_module) do
          double("Registration::Registration", new: registration)
        end

        let(:registration) do
          instance_double("Registration::Registration", activated_products: [product])
        end

        let(:product) do
          double("SUSE::Connect::Remote::Product", repositories: [scc_repo])
        end

        let(:scc_repo) do
          { "url" => "http://xxx.url" }
        end

        before do
          allow(subject).to receive(:require).with("registration/registration")
          stub_const("Registration::Registration", registration_module)
        end

        it "does not export such an addon" do
          expect(Yast::AddOnOthers.Export).to eq("add_on_others" => [])
        end
      end
    end
  end
end
