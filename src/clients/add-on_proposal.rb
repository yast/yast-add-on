# encoding: utf-8

# File:	add-on_proposal.ycp
#
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# Purpose:	Proposal function dispatcher - add-no products
#
#		See also file proposal-API.txt for details.
module Yast
  class AddOnProposalClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "add-on"

      Yast.import "Label"
      Yast.import "Wizard"
      Yast.import "AddOnProduct"
      Yast.import "WorkflowManager"

      Yast.include self, "add-on/add-on-workflow.rb"

      @func = Convert.to_string(WFM.Args(0))
      @param = Convert.to_map(WFM.Args(1))
      @ret = {}

      if @func == "MakeProposal"
        @force_reset = Ops.get_boolean(@param, "force_reset", false)
        @language_changed = Ops.get_boolean(@param, "language_changed", false)

        @items = Builtins.maplist(AddOnProduct.add_on_products) do |product|
          data = Pkg.SourceGeneralData(Ops.get_integer(product, "media", -1))
          # placeholder for unknown path
          dir = Ops.get_locale(data, "product_dir", product.fetch( "product_dir", _("Unknown")))
          dir = "/" if dir == ""
          # summary item, %1 is product name, %2 media URL, %3 directory on media
          Builtins.sformat(
            "%1 (Media %2, directory %3)",
            Ops.get_string(product, "product", ""),
            Ops.get_locale(data, "url", product.fetch( "media_url", _("Unknown"))),
            dir
          )
        end
        if Builtins.size(@items) == 0
          # summary string
          @items = [_("No add-on product selected for installation")]
        end

        WorkflowManager.RedrawWizardSteps

        @ret = { "raw_proposal" => @items }
      elsif @func == "AskUser"
        Wizard.CreateDialog
        @result = RunAddOnMainDialog(
          false,
          true,
          true,
          Label.BackButton,
          Label.OKButton,
          Label.CancelButton,
          false
        )
        UI.CloseDialog

        # Fill return map

        @ret = { "workflow_sequence" => @result, "mode_changed" => false }
      elsif @func == "Description"
        # Fill return map.
        #
        # Static values do just nicely here, no need to call a function.

        @ret = {
          # this is a heading
          "rich_text_title" => _("Add-On Products"),
          # this is a menu entry
          "menu_title"      => _("Add-&on Products"),
          "id"              => "add_on"
        }
      end

      deep_copy(@ret)
    end
  end
end

Yast::AddOnProposalClient.new.main
