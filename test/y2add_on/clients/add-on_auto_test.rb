#!/usr/bin/env rspec

require_relative "../../test_helper"
require "add-on/clients/add-on_auto"

Yast.import "Packages"

describe Yast::AddOnAutoClient do
  describe "#main" do
    before do
      allow(Yast::WFM).to receive(:Args).with(no_args).and_return([func])
      allow(Yast::WFM).to receive(:Args).with(0).and_return(func)
    end

    context "when 'func' is 'Import'" do
      let(:func) { "Import" }
      let(:params) do
        { "add_on_products" => add_on_products }
      end

      before do
        allow(Yast::WFM).to receive(:Args).with(no_args).and_return([func, params])
        allow(Yast::WFM).to receive(:Args).with(1).and_return(params)
      end

      context "and completly valid 'add_on_products' param is given" do
        let(:add_on_products) do
          [
            {
              "alias"       => "valid_add_on",
              "media_url"   => "http://product.url",
              "name"        => "updated_repo",
              "priority"    => 20,
              "product_dir" => "/"
            }
          ]
        end

        it "imports all add-on products given" do
          expect(Yast::AddOnProduct).to receive(:Import).with(params)

          subject.main
        end
      end

      context "and there are missed medie_url values in given 'add_on_products'" do
        let(:add_on_products) do
          [
            {
              "alias"       => "valid_add_on",
              "media_url"   => "http://product.url",
              "name"        => "updated_repo",
              "priority"    => 20,
              "product_dir" => "/"
            },
            {
              "alias"       => "not_valid_add_on",
              "name"        => "updated_repo",
              "priority"    => 20,
              "product_dir" => "/"
            }
          ]
        end
        let(:valid_add_on_products) do
          [
            {
              "alias"       => "valid_add_on",
              "media_url"   => "http://product.url",
              "name"        => "updated_repo",
              "priority"    => 20,
              "product_dir" => "/"
            }
          ]
        end

        let(:rejected_package_error) { "Missing <media_url> value in the 2. add-on-product definition" }
        let(:missed_media_url_error) { /Missing mandatory <media_url> value at index 2/ }

        it "asks to user about reject them" do
          expect(Yast::Popup).to receive(:ContinueCancel).with(missed_media_url_error)

          subject.main
        end

        it "rejects them if user decides to continue" do
          allow(Yast::Popup).to receive(:ContinueCancel).and_return(true)

          expect(Yast::AddOnProduct).to receive(:Import).with("add_on_products" => valid_add_on_products)

          subject.main
        end

        it "returns false (does nothing) if user decides to abort" do
          allow(Yast::Popup).to receive(:ContinueCancel).and_return(false)

          expect(Yast::AddOnProduct).to_not receive(:Import)

          # expect(subject.main).to be_falsey
        end
      end

      context "and 'add_on_products' param is NOT given" do
        let(:params) { { something: nil } }

        # it "should does nothing" do
        it "sets 'add_on_products' to empty array" do
          expect(Yast::AddOnProduct).to receive(:Import).with("add_on_products" => [])

          subject.main
        end
      end
    end

    context "when 'func' is 'Summary'" do
      let(:func) { "Summary" }
      let(:add_on_products) do
        [
          {
            "alias"       => "valid_add_on",
            "media_url"   => "http://product.url",
            "name"        => "updated_repo",
            "priority"    => 20,
            "product_dir" => "/"
          },
          {
            "alias"       => "not_valid_add_on",
            "media_url"   => "http://media.url",
            "name"        => "updated_repo",
            "priority"    => 20,
            "product_dir" => "/"
          }
        ]
      end
      let(:expected_output) do
        [
          "<ul>",
          "<li>Media: http://product.url, Path: /, Product: </li>",
          "<li>Media: http://media.url, Path: /, Product: </li>",
          "</ul>"
        ].join("\n")
      end

      it "returns an unordered list sumarizing current add_on_product" do
        allow(Yast::AddOnProduct).to receive(:add_on_products).and_return(add_on_products)
        expect(subject.main).to eq(expected_output)
      end
    end

    context "when 'func' is 'GetModified'" do
      let(:func) { "GetModified" }

      context "and configuration did changed" do
        before do
          allow(Yast::AddOnProduct).to receive(:modified).and_return(true)
        end

        it "returns true" do
          expect(subject.main).to be_truthy
        end
      end

      context "and configuration did not changed" do
        before do
          allow(Yast::AddOnProduct).to receive(:modified).and_return(false)
        end

        it "returns true" do
          expect(subject.main).to be_falsey
        end
      end
    end

    context "when 'func' is 'SetModified'" do
      let(:func) { "SettModified" }

      it "sets configuration as changed" do
        allow(Yast::AddOnProduct).to receive(:modified=).with(true)

        subject.main
      end
    end

    context "when 'func' is 'Reset'" do
      let(:func) { "Reset" }

      it "resets configuration" do
        allow(Yast::AddOnProduct).to receive(:add_on_products=).with([])

        subject.main
      end
    end

    context "when 'func' is 'Change'" do
      let(:func) { "Change" }

      before do
        allow(Yast::Wizard).to receive(:CreateDialog)
        allow(Yast::AutoinstSoftware).to receive(:pmInit)
      end

      it "runs add-on main dialog" do
        expect(subject).to receive(:RunAddOnMainDialog)

        subject.main
      end

      it "returns chosen action" do
        allow(subject).to receive(:RunAddOnMainDialog).and_return(:next)

        expect(subject.main).to be(:next)
      end
    end

    context "when 'func' is 'Export'" do
      let(:func) { "Export" }

      # FIXME: use a more reallistinc configuration data example
      it "returns configuration data" do
        allow(Yast::AddOnProduct).to receive(:Export).and_return("configuration data")

        expect(subject.main).to eq("configuration data")
      end
    end

    context "when 'func' is 'Write'" do
      let(:func) { "Write" }
      let(:repos) do
        [
          {
            "SrcId"        => 1,
            "autorefresh"  => true,
            "enabled"      => true,
            "keeppackaged" => false,
            "name"         => "repo_to_be_updated",
            "priority"     => 99,
            "service"      => ""
          },
          {
            "SrcId"        => 2,
            "autorefresh"  => true,
            "enabled"      => true,
            "keeppackaged" => false,
            "name"         => "untouched_repo",
            "priority"     => 99,
            "service"      => ""
          }
        ]
      end

      context "and there are add-ons products" do
        let(:add_on_products) do
          [
            {
              "alias"       => "produc_alias",
              "media_url"   => "http://product.url",
              "name"        => "updated_repo",
              "priority"    => 20,
              "product_dir" => "/"
            }
          ]
        end
        let(:repos_to_store) do
          [
            {
              "SrcId"        => 1,
              "autorefresh"  => true,
              "enabled"      => true,
              "keeppackaged" => false,
              "name"         => "updated_repo",
              "priority"     => 20,
              "service"      => ""
            },
            {
              "SrcId"        => 2,
              "autorefresh"  => true,
              "enabled"      => true,
              "keeppackaged" => false,
              "name"         => "untouched_repo",
              "priority"     => 99,
              "service"      => ""
            }
          ]
        end

        before do
          allow(Yast::AddOnProduct).to receive(:add_on_products).and_return(add_on_products)
          allow(Yast::Pkg).to receive(:SourceEditSet)
          allow(Yast::Pkg).to receive(:SourceCreate).and_return(1)
          allow(Yast::Pkg).to receive(:SourceEditGet).and_return(repos)
        end

        it "stores repos according to information given" do
          expect(Yast::Pkg).to receive(:SourceEditSet).with(repos_to_store)

          subject.main
        end
      end
    end

    context "when 'func' is 'Read'" do
      let(:func) { "Read" }

      context "and cannot lock package" do
        before do
          allow(Yast::PackageLock).to receive(:Check).and_return(false)
        end

        it "returns false" do
          expect(subject.main).to be_falsey
        end
      end

      context "and can lock package" do
        before do
          allow(Yast::PackageLock).to receive(:Check).and_return(true)
          allow(Yast::Pkg).to receive(:SourceStartManager)
        end

        it "reads add-ons configuration from the current system" do
          expect(subject).to receive(:ReadFromSystem)

          subject.main
        end
      end
    end

    context "when 'fucn' is not valid" do
      let(:func) { "Whatever" }

      it "logs an `unknow function` error" do
        allow(Yast::Builtins).to receive(:y2error).with("unknown function: %1", "Whatever")

        subject.main
      end

      it "returns false" do
        expect(subject.main).to be_falsey
      end
    end
  end
end
