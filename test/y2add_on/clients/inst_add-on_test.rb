require_relative "../../test_helper"
require "add-on/clients/inst_add-on"

Yast.import "Packages"
Yast.import "Linuxrc"
Yast.import "Installation"
Yast.import "AddOnProduct"

describe Yast::InstAddOnClient do
  describe "#main" do
    let(:addons) { "dvd:///?devices=/dev/sr0" }
    let(:inst_url) { "dvd:///?devices=/dev/disk/by-id/ata-QEMU_DVD-ROM_QM00001" }
    let(:skip_add_ons) { false }
    let(:add_on_selected) { false }

    before do
      allow(Yast::Packages).to receive(:SelectProduct)
      allow(Yast::Linuxrc).to receive(:InstallInf).with("addon").and_return(addons)
      allow(subject).to receive(:NetworkSetupForAddons).and_return(:next)
      allow(subject).to receive(:InstallProduct)
      allow(Yast::AddOnProduct).to receive(:skip_add_ons).and_return(skip_add_ons)
      allow(Yast::Installation).to receive(:add_on_selected).and_return(add_on_selected)
      allow(Yast::InstURL).to receive(:installInf2Url).and_return(inst_url)
      allow(subject).to receive(:RunAddOnMainDialog).and_return(:next)
    end

    context "when add-on products selection should be skipped" do
      let(:skip_add_ons) { true }

      it "returns :auto" do
        expect(subject.main).to eq(:auto)
      end
    end

    context "when no add-ons are given" do
      let(:addons) { nil }

      it "returns :next" do
        expect(subject.main).to eq(:auto)
      end
    end

    context "when an add-on is given" do
      let(:addons) { "dvd:///?devices=/dev/sr0" }
      let(:realpath) { "/dev/sr0" }

      before do
        allow(File).to receive(:realpath).with("/dev/sr0").and_return("/dev/sr0")
        allow(File).to receive(:realpath).with("/dev/disk/by-id/ata-QEMU_DVD-ROM_QM00001")
          .and_return(realpath)
        allow(subject).to receive(:createSourceImpl)
      end

      context "and it is using the same CD/DVD than instsys" do
        let(:accept_dialog) { true }

        before do
          allow(Yast::AddOnProduct).to receive(:AskForCD).and_return(accept_dialog)
        end

        it "asks the user to change the media" do
          expect(Yast::AddOnProduct).to receive(:AskForCD).with(addons, "")
            .and_return(true)
          subject.main
        end

        it "adds the given add-on" do
          expect(subject).to receive(:createSourceImpl).with(addons, *any_args)
          subject.main
        end

        context "and the user rejects the dialog" do
          let(:accept_dialog) { false }

          it "does not add the add-on" do
            expect(subject).to_not receive(:createSourceImpl)
            subject.main
          end
        end
      end

      context "and it is using a different CD/DVD than instsys" do
        let(:realpath) { "/dev/sr1" }

        it "does not ask the user to change the media" do
          expect(Yast::AddOnProduct).to_not receive(:AskForCD)
          subject.main
        end

        it "adds the given add-on" do
          expect(subject).to receive(:createSourceImpl).with(addons, *any_args)
          subject.main
        end
      end

      context "and the device does not exist" do
        before do
          allow(File).to receive(:realpath).with("/dev/sr0").and_raise(Errno::ENOENT)
        end

        it "does not ask the user to change the media" do
          expect(Yast::AddOnProduct).to_not receive(:AskForCD)
          subject.main
        end
      end

      context "and it is not using a CD/DVD" do
        let(:addons) { "http://example.net/add-on" }

        it "does not ask the user to change the media" do
          expect(Yast::AddOnProduct).to_not receive(:AskForCD)
          subject.main
        end

        it "adds the given add-on" do
          expect(subject).to receive(:createSourceImpl).with(addons, *any_args)
          subject.main
        end
      end

      context "and it is not installing from a CD/DVD" do
        let(:inst_url) { "http://example.net/sle/DVD1" }

        it "does not ask the user to change the media" do
          expect(Yast::AddOnProduct).to_not receive(:AskForCD)
          subject.main
        end

        it "adds the given add-on" do
          expect(subject).to receive(:createSourceImpl).with(addons, *any_args)
          subject.main
        end
      end
    end

    context "when UI is actually needed" do
      let(:add_on_selected) { true }

      it "runs add-on main dialog"
      it "starts workflow"
    end
  end
end
