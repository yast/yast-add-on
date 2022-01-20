#!/usr/bin/env rspec

# Copyright (c) [2018-2021] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require_relative "../../test_helper"
require "add-on/clients/add-on_auto"

Yast.import "Packages"

describe Yast::AddOnAutoClient do
  subject(:client) { described_class.new }

  describe "#import" do
    let(:params) do
      { "add_on_products" => add_on_products,
        "add_on_others"   => add_on_others }
    end

    context "when no data is given" do
      it "does not try to import add-on products" do
        expect(Yast::AddOnProduct).to_not receive(:Import)

        client.import(nil)
      end

      it "returns true" do
        expect(client.import(nil)).to eq(true)
      end
    end

    context "when given data only contains valid add-ons" do
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

      let(:add_on_others) do
        [
          {
            "alias"       => "user defined",
            "media_url"   => "http://xxx.url",
            "name"        => "user_defined",
            "priority"    => 19,
            "product_dir" => "/"
          }
        ]
      end

      it "imports all add-on products given" do
        expect(Yast::AddOnProduct).to receive(:Import).with(
          "add_on_products" => add_on_products + add_on_others
        )

        client.import(params)
      end
    end

    context "when given data contains a not valid add-on" do
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
      let(:add_on_others) { [] }

      let(:rejected_package_error) { "Missing <media_url> value in the 2. add-on-product definition" }
      let(:missed_media_url_error) { /Missing mandatory <media_url> value at index 2/ }

      it "asks to user about reject them" do
        expect(Yast::Popup).to receive(:ContinueCancel).with(missed_media_url_error)

        client.import(params)
      end

      it "rejects them if user decides to continue" do
        allow(Yast::Popup).to receive(:ContinueCancel).and_return(true)

        expect(Yast::AddOnProduct).to receive(:Import).with("add_on_products" => valid_add_on_products)

        client.import(params)
      end

      it "returns false (does nothing) if user decides to abort" do
        allow(Yast::Popup).to receive(:ContinueCancel).and_return(false)

        expect(Yast::AddOnProduct).to_not receive(:Import)
      end
    end
  end

  describe "#summary" do
    let(:add_on_products) do
      [
        {
          "alias"       => "valid_add_on",
          "media_url"   => "dvd:///product",
          "name"        => "updated_repo",
          "priority"    => 20,
          "product_dir" => ""
        },
        {
          "alias"       => "valid_add_on",
          "media_url"   => "http://product.url",
          "name"        => "updated_repo",
          "priority"    => 20,
          "product_dir" => "/",
          "product"     => "Example product"
        },
        {
          "alias"       => "not_valid_add_on",
          "media_url"   => "http://product.url",
          "name"        => "updated_repo",
          "priority"    => 20,
          "product_dir" => "/path/to/product"
        },
        {
          "alias"       => "not_valid_add_on",
          "media_url"   => "http://product.url",
          "name"        => "updated_repo",
          "priority"    => 20,
          "product_dir" => "/path/to/product",
          "product"     => "<strong>Example</strong> product"
        }
      ]
    end
    let(:expected_output) do
      [
        "<ul>",
        "<li>URL: dvd:///product</li>",
        "<li>URL: http://product.url, Product: Example product</li>",
        "<li>URL: http://product.url, Path: /path/to/product</li>",
        "<li>URL: http://product.url, Path: /path/to/product, Product: &lt;strong&gt;Example&lt;/strong&gt; product</li>",
        "</ul>"
      ].join("\n")
    end

    it "returns an unordered list sumarizing current add_on_product" do
      allow(Yast::AddOnProduct).to receive(:add_on_products).and_return(add_on_products)

      expect(client.summary).to eq(expected_output)
    end
  end

  describe "#modified?" do
    context "and configuration did changed" do
      before do
        allow(Yast::AddOnProduct).to receive(:modified).and_return(true)
      end

      it "returns true" do
        expect(client.modified?).to be_truthy
      end
    end

    context "and configuration did not changed" do
      before do
        allow(Yast::AddOnProduct).to receive(:modified).and_return(false)
      end

      it "returns true" do
        expect(client.modified?).to be_falsey
      end
    end
  end

  describe "#modified" do
    it "sets configuration as changed" do
      allow(Yast::AddOnProduct).to receive(:modified=).with(true)

      client.modified
    end
  end

  describe "#reset" do
    it "resets configuration" do
      allow(Yast::AddOnProduct).to receive(:add_on_products=).with([])

      client.reset
    end
  end

  describe "#change" do
    before do
      allow(Yast::Wizard).to receive(:CreateDialog)
      allow(Yast::AutoinstSoftware).to receive(:pmInit)
    end

    it "runs add-on main dialog" do
      expect(client).to receive(:RunAddOnMainDialog)

      client.change
    end

    it "returns chosen action" do
      allow(client).to receive(:RunAddOnMainDialog).and_return(:next)

      expect(client.change).to be(:next)
    end
  end

  describe "#export" do
    let(:add_on_products) do
      { "add_on_products" => [
        { "product_dir" => "/Module-Desktop-Applications",
          "product"     => "sle-module-desktop-applications",
          "media_url"   => "dvd:/?devices=/dev/sr1" },
        { "product_dir" => "/Module-Basesystem",
          "product"     => "sle-module-basesystem",
          "media_url"   => "dvd:/?devices=/dev/sr1" }
      ] }
    end
    let(:add_on_others) do
      { "add_on_others" => [
        { "product_dir" => "/Module-Desktop-Applications",
          "product"     => "sle-module-desktop-applications",
          "media_url"   => "dvd:/?devices=/dev/sr1" }

      ] }
    end

    it "returns add-on products merged with other add-ons if they are non empty" do
      expect(Yast::AddOnProduct).to receive(:Export).and_return(add_on_products)
      expect(Yast::AddOnOthers).to receive(:Export).and_return(add_on_others)

      expect(client.export).to eq(add_on_products.merge(add_on_others))
    end

    it "returns just non empty type of addons" do
      expect(Yast::AddOnProduct).to receive(:Export).and_return(add_on_products)
      expect(Yast::AddOnOthers).to receive(:Export).and_return({})

      expect(client.export).to eq(add_on_products)
    end

    it "returns empty hash if all types are empty" do
      expect(Yast::AddOnProduct).to receive(:Export).and_return({})
      expect(Yast::AddOnOthers).to receive(:Export).and_return({})

      expect(client.export).to eq({})
    end
  end

  describe "#write" do
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

    context "when there are add-ons products" do
      let(:ask_on_error) { true }
      let(:unexpanded_url) { "RELURL://product-$releasever.url" }
      let(:expanded_url) { "RELURL://product-15.0.url" }
      let(:add_on_products) do
        [
          {
            "alias"        => "produc_alias",
            "ask_on_error" => ask_on_error,
            "media_url"    => unexpanded_url,
            "priority"     => 20,
            "product_dir"  => "/"
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
            "name"         => "repo_to_be_updated",
            "raw_name"     => "Updated repo",
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
        allow(Yast::Pkg).to receive(:SourceEditSet)
        allow(Yast::Pkg).to receive(:SourceReleaseAll)
        allow(Yast::Pkg).to receive(:SourceCreate).and_return(1)
        allow(Yast::Pkg).to receive(:SourceEditGet).and_return(repos)
        allow(Yast::Pkg).to receive(:ExpandedUrl)
        # For testing #preferred_name_for" indirectly
        allow(Yast::Pkg).to receive(:RepositoryScan)
          .with(anything)
          .and_return([["Updated repo", "/"]])

        allow(Yast::AddOnProduct).to receive(:add_on_products).and_return(add_on_products)

        # For testing regresion with $releasever (bsc#1194851)
        allow(Yast::AddOnProduct).to receive(:SetRepoUrlAlias).and_return(expanded_url)
      end

      it "stores repos according to information given" do
        expect(Yast::Pkg).to receive(:SourceEditSet).with(repos_to_store)

        client.write
      end

      it "releases the media accessors" do
        expect(Yast::Pkg).to receive(:SourceReleaseAll)

        client.write
      end

      # For testing regresion with $releasever (bsc#1194851)
      it "restores the unexpanded URL" do
        expect(Yast::Pkg).to receive(:SourceChangeUrl).with(1, unexpanded_url)

        client.write
      end

      context "and product creation fails" do
        before do
          allow(Yast::Report).to receive(:Error)
          allow(Yast::Pkg).to receive(:SourceCreate).and_return(-1)
          allow(Yast::Popup).to receive(:ContinueCancel).and_return(retry_on_error, false)
        end

        let(:retry_on_error) { true }

        context "ask_on_error=true" do
          it "ask the user to make it available" do
            expect(Yast::Popup).to receive(:ContinueCancel)

            client.write
          end

          context "and user wants to retry" do
            let(:retry_on_error) { true }

            it "tries it again" do
              expect(Yast::Pkg).to receive(:SourceCreate).with(expanded_url, "/").twice

              client.write
            end

            it "does not reports an error while retrying" do
              expect(Yast::Report).to receive(:Error).exactly(1).times

              client.write
            end
          end

          context "and user decides not retrying" do
            let(:retry_on_error) { false }

            it "does not try it again" do
              expect(Yast::Pkg).to receive(:SourceCreate).once

              client.write
            end

            it "reports an error" do
              expect(Yast::Report).to receive(:Error)

              client.write
            end
          end
        end

        context "ask_on_error=false" do
          let(:ask_on_error) { false }

          it "does not ask to make it available" do
            expect(Yast::Popup).to_not receive(:ContinueCancel)

            client.write
          end

          it "reports the error" do
            expect(Yast::Report).to receive(:Error)

            client.write
          end
        end
      end
    end
  end

  describe "#read" do
    context "when package manager cannot be locked" do
      before do
        allow(Yast::PackageLock).to receive(:Check).and_return(false)
      end

      it "returns false" do
        expect(client.read).to be_falsey
      end
    end

    context "when package manager can be locked" do
      before do
        allow(Yast::PackageLock).to receive(:Check).and_return(true)
        allow(Yast::Pkg).to receive(:SourceStartManager)
      end

      it "reads add-ons configuration from the current system" do
        expect(client).to receive(:ReadFromSystem)

        client.read
      end
    end
  end
end
