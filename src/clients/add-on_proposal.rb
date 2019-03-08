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

      func = Convert.to_string(WFM.Args(0))
      ret = {}

      if func == "MakeProposal"
        items = Builtins.maplist(AddOnProduct.add_on_products) do |product|
          data = Pkg.SourceGeneralData(Ops.get_integer(product, "media", -1))
          dir = data["product_dir"]

          # no subdirectory used, do not print it
          if dir.nil? || dir.empty? || dir == "/"
            # TRANSLATORS: add on product summary item,
            #   %{name} is the product name,
            #   %{url} is the repository URL
            _("%{name} (%{url})") % {
              name: product["product"],
              url: data["url"] || _("Unknown")
            }
          else
            # TRANSLATORS: add on product summary item,
            #   special case when a subdirectory is defined
            #   %{name} is the product name,
            #   %{url} is the repository URL,
            #   %{dir}
            _("%{name} (%{url}, directory %{dir})") % {
              dir: dir,
              name: product["product"],
              url: data["url"] || _("Unknown")
            }
          end
        end

        if items.empty?
          # summary string
          items << _("No add-on product selected for installation")
        end

        WorkflowManager.RedrawWizardSteps

        ret = { "raw_proposal" => items }
      elsif func == "AskUser"
        Wizard.CreateDialog
        result = RunAddOnMainDialog(
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
        ret = { "workflow_sequence" => result, "mode_changed" => false }
      elsif func == "Description"
        # Fill return map.
        ret = {
          # this is a heading
          "rich_text_title" => link_title,
          # this is a menu entry
          "menu_title"      => _("Add-&on Products"),
          "id"              => "add_on"
        }
      end

      ret
    end

  private

    # Build the dialog title (depending on the current UI)
    # @return [String] the translated title
    def link_title
      if UI.TextMode
        # TRANSLATORS: dialog title (short form for text mode)
        _("Add-On Products")
      else
        # TRANSLATORS: dialog title (long form for GUI, but still keep as short as possible)
        _("Add-On Products (Products, Extensions, Modules, Other Repositories)")
      end
    end
  end
end

Yast::AddOnProposalClient.new.main
