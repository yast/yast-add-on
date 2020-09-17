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
      allow(Yast::Pkg).to receive(:SourceGetCurrent).and_return([], [42,43])
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
          [Y2Packager::Resolvable.new(p1), Y2Packager::Resolvable.new(p2)])
        expect(Yast::Pkg).to receive(:ResolvableInstall).with("product1", :product)
        expect(Yast::Pkg).to receive(:ResolvableInstall).with("product2", :product)

        AddonIncludeTester.InstallProduct
      end

      it "ignores the products from other repositories" do
        expect(Y2Packager::Resolvable).to receive(:find).and_return(
          [Y2Packager::Resolvable.new(p1.merge("source" => 1)), Y2Packager::Resolvable.new(p2.merge("source" => 2))])
        expect(Yast::Pkg).to_not receive(:ResolvableInstall)

        AddonIncludeTester.InstallProduct
      end

      it "ignores the already selected repositories" do
        expect(Y2Packager::Resolvable).to receive(:find).and_return(
          [Y2Packager::Resolvable.new(p1.merge("status" => :selected)),
           Y2Packager::Resolvable.new(p2.merge("status" => :selected))])
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

  describe "#RunAddOnMainDialog" do
    before do
      allow(Yast::Pkg).to receive(:SourceReleaseAll)
      allow(Yast::Stage).to receive(:initial).and_return(true)
      allow(AddonIncludeTester).to receive(:HasInsufficientMemory).and_return(false)
      allow(Yast::WorkflowManager).to receive(:SetBaseWorkflow)
      allow(Yast::Wizard).to receive(:SetTitleIcon)
      allow(AddonIncludeTester).to receive(:Redraw)
      allow(Yast::AddOnProduct).to receive(:PrepareForRegistration)
      allow(Yast::AddOnProduct).to receive(:Integrate)
      allow(Yast::AddOnProduct).to receive(:ProcessRegistration)
      allow(Yast::AddOnProduct).to receive(:ReIntegrateFromScratch)
      allow(Yast::Wizard).to receive(:RestoreBackButton)
      allow(Yast::Wizard).to receive(:RestoreAbortButton)
      allow(Yast::Wizard).to receive(:RestoreNextButton)
      allow(Yast::UI).to receive(:UserInput).and_return(:next)
    end

    after do
      # reset the changed flag back (for the other tests)
      Yast::AddOnAddOnWorkflowInclude.class_variable_set(:@@media_addons_selected, false)
    end

    context "a DUD add-on present, using Full medium" do
      before do
        allow(Yast::AddOnProduct).to receive(:add_on_products).and_return([
          {
            "media" => 4,
            "product" => "Driver Update 0",
            "autoyast_product" => "Driver Update 0",
            "media_url" => "dir:///update/000/repo?alias=DriverUpdate0",
            "product_dir" => "",
            "priority" => 50
          }
        ])
        allow(Y2Packager::MediumType).to receive(:offline?).and_return(true)
      end

      it "asks for the media addons and stores the state" do
        expect(AddonIncludeTester).to receive(:RunWizard).and_return(:next)
        expect { AddonIncludeTester.RunAddOnMainDialog(true, true, true, "", "", "", true) }.to \
          change { Yast::AddOnAddOnWorkflowInclude.class_variable_get(:@@media_addons_selected) } \
          .from(false).to(true)
      end
    end
  end
end
