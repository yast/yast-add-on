#! /usr/bin/env rspec

require_relative "./test_helper"

require_relative "../src/include/add-on/add-on-workflow.rb"

# just a dummy class for including the tested methods
class AddOnAddOnWorkflowIncludeTest
  include Yast::AddOnAddOnWorkflowInclude
end

Yast.import "AddOnProduct"
Yast.import "SourceDialogs"

describe Yast::AddOnAddOnWorkflowInclude do
  subject { AddOnAddOnWorkflowIncludeTest.new }

  describe ".media_type_selection" do
    context "Full medium installation with no add-ons yet" do
      let(:registration) { double("Registration::Registration", is_registered?: registered?) }

      before do
        allow(Yast::AddOnProduct).to receive(:add_on_products).and_return([])
        allow(Yast::Stage).to receive(:initial).and_return(true)
        allow(Y2Packager::MediumType).to receive(:offline?).and_return(true)
        allow(Yast::InstURL).to receive(:installInf2Url)
        allow(Yast::SourceDialogs).to receive(:SetURL)

        allow(Yast::SourceDialogs).to receive(:GetURL)
        allow(Yast::SourceDialogs).to receive(:addon_enabled)
        allow(subject).to receive(:TypeDialogOpts)

        stub_const("Registration::Registration", registration)
        allow(subject).to receive(:require).with("registration/registration")
      end

      after do
        # reset the changed flag back (for the other tests)
        Yast::AddOnAddOnWorkflowInclude.class_variable_set(:@@media_addons_selected, false)
      end
  
      context "not registered" do
        let(:registered?) { false }

        it "preselects the installation URL for the add-ons" do
          expect(Yast::InstURL).to receive(:installInf2Url)
          expect(Yast::SourceDialogs).to receive(:SetURL)
          subject.media_type_selection
        end
  
        it "returns the :finish symbol" do
          expect(subject.media_type_selection).to eq(:finish)
          subject.media_type_selection

        end
      end
      
      context "registered" do
        let(:registered?) { true }

        it "does not preselect the installation URL for the add-ons" do
          expect(Yast::InstURL).to_not receive(:installInf2Url)
          expect(Yast::SourceDialogs).to_not receive(:SetURL)
          subject.media_type_selection
        end
  
        it "returns the user input" do
          allow(subject).to receive(:TypeDialogOpts).and_return(:next)
          expect(subject.media_type_selection).to eq(:next)
        end
      end
    end
  end
end
