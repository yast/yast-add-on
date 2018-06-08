#!/usr/bin/env rspec

require_relative "test_helper"

require "yast"
require_relative "../src/clients/add-on_auto"

describe Yast::AddOnAutoClient do
  describe "#main" do
    before do
      allow(Yast::WFM).to receive(:Args).with(no_args).and_return([func])
      allow(Yast::WFM).to receive(:Args).with(0).and_return(func)
    end

    context "when 'func' is 'Write'" do
      let(:func) { "Write" }
      let(:repos) do
        [
          { "SrcId"        => 1,
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
  end
end
