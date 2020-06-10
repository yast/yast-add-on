require_relative "./test_helper"

Yast.import "Pkg"
Yast.import "Sequencer"
Yast.import "Packages"

# just a wrapper class for the repositories_include.rb
module Yast
  class AddOnWorkflowIncludeTesterClass < Module
    extend Yast::I18n

    def main
      Yast.include self, "add-on/add-on-workflow.rb"
    end
  end
end

AddonIncludeTester = Yast::AddOnWorkflowIncludeTesterClass.new
AddonIncludeTester.main

describe "Yast::AddOnWorkflowInclude" do
  subject { AddonIncludeTester }

  describe "#MediaSelect" do
    before do
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([])
      allow(Yast::Sequencer).to receive(:Run).and_return(:next)
      allow(Yast::Packages).to receive(:AdjustSourcePropertiesAccordingToProduct)
      allow(subject).to receive(:AddAddOnToStore)
      allow(Yast::Pkg).to receive(:SourceRefreshNow)
      allow(Yast::Pkg).to receive(:SourceLoad)
      allow(Yast::Pkg).to receive(:SourceSaveAll)
      allow(Yast::AddOnProduct).to receive(:last_ret=)
    end

    it "returns the UI symbol" do
      expect(Yast::Sequencer).to receive(:Run).and_return(:next)
      expect(subject.MediaSelect).to eq(:next)
    end

    it "refreshes all added repositories and loads the available packages" do
      # no initial repository, then 2 repositories added
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([], [42, 43])
      expect(Yast::Pkg).to receive(:SourceRefreshNow).with(42)
      expect(Yast::Pkg).to receive(:SourceRefreshNow).with(43)
      expect(Yast::Pkg).to receive(:SourceLoad)

      subject.MediaSelect
    end
  end

  describe "#InstallProduct" do
    context "no repository has been added" do
      before do
        AddonIncludeTester.instance_variable_set("@added_repos", [])
      end

      it "does not select any product" do
        expect(Yast::Pkg).to_not receive(:ResolvableInstall)
        AddonIncludeTester.InstallProduct
      end

      it "returns :next" do
        expect(AddonIncludeTester.InstallProduct).to eq(:next)
      end
    end

    context "some repositories have been added" do
      # add-on products in the repositories
      let(:p1) { { "name" => "product1", "source" => 42, "status" => :available } }
      let(:p2) { { "name" => "product2", "source" => 43, "status" => :available } }

      before do
        AddonIncludeTester.instance_variable_set("@added_repos", [42, 43])
      end

      it "returns :next" do
        allow(Y2Packager::Resolvable).to receive(:find).and_return([])
        allow(Yast::Pkg).to receive(:ResolvableInstall)
        expect(AddonIncludeTester.InstallProduct).to eq(:next)
      end

      it "selects the available products from the added repositories" do
        expect(Y2Packager::Resolvable).to receive(:find).and_return(
          [Y2Packager::Resolvable.new(p1), Y2Packager::Resolvable.new(p2)]
        )
        expect(Yast::Pkg).to receive(:ResolvableInstall).with("product1", :product)
        expect(Yast::Pkg).to receive(:ResolvableInstall).with("product2", :product)

        AddonIncludeTester.InstallProduct
      end

      it "ignores the products from other repositories" do
        expect(Y2Packager::Resolvable).to receive(:find).and_return(
          [Y2Packager::Resolvable.new(p1.merge("source" => 1)), Y2Packager::Resolvable.new(p2.merge("source" => 2))]
        )
        expect(Yast::Pkg).to_not receive(:ResolvableInstall)

        AddonIncludeTester.InstallProduct
      end

      it "ignores the already selected repositories" do
        expect(Y2Packager::Resolvable).to receive(:find).and_return(
          [Y2Packager::Resolvable.new(p1.merge("status" => :selected)),
           Y2Packager::Resolvable.new(p2.merge("status" => :selected))]
        )
        expect(Yast::Pkg).to_not receive(:ResolvableInstall)

        AddonIncludeTester.InstallProduct
      end
    end
  end

  describe "#RunAddProductWorkflow" do
    before do
      allow(Yast::WFM).to receive(:CallFunction).with("inst_addon_update_sources", [])
      allow(Yast::Pkg).to receive(:SourceReleaseAll)
      allow(AddonIncludeTester).to receive(:Write)
      AddonIncludeTester.instance_variable_set("@added_repos", [1, 2])
    end

    it "installs the selected products at once" do
      expect(Yast::WorkflowManager).to receive(:GetCachedWorkflowFilename).and_return(nil).twice
      expect(Yast::AddOnProduct).to receive(:DoInstall).with(install_packages: false).twice
      expect(Yast::AddOnProduct).to receive(:DoInstall_NoControlFile)
      AddonIncludeTester.RunAddProductWorkflow
    end

    it "handles addons with installation.xml" do
      expect(Yast::WorkflowManager).to receive(:GetCachedWorkflowFilename).and_return("foo").twice
      expect(Yast::AddOnProduct).to receive(:DoInstall).twice
      expect(Yast::AddOnProduct).to_not receive(:DoInstall_NoControlFile)
      AddonIncludeTester.RunAddProductWorkflow
    end
  end
end
