# encoding: utf-8

# File:	clients/add-on.ycp
# Package:	yast2-installation
# Summary:	Install an add-on product
# Authors:	Jiri Srain <jsrain@suse.de>
#
module Yast
  class AddOnClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "add-on"

      Yast.import "AddOnProduct"
      Yast.import "Confirm"
      Yast.import "PackageLock"
      Yast.import "PackageCallbacks"
      Yast.import "Report"
      Yast.import "Wizard"
      Yast.import "GetInstArgs"
      Yast.import "Mode"
      Yast.import "CommandLine"
      Yast.import "Directory"

      Yast.include self, "add-on/add-on-workflow.rb"
      CommandLine.Run(
        "id"         => "add_on",
        # Command line help text for the repository module, %1 is "zypper"
        "help"       => format(
          _(
            "Add On Management - This module does not support the command line " \
              "interface, use '%{zypper}' instead for adding repository or " \
              "'%{SUSEConnect}' to register new addon."
          ),
          { zypper: "zypper", SUSEConnect: "SUSEConnect" }
        ),
        "guihandler" => fun_ref(method(:run_GUI), "symbol ()")
      )
    end

    def run_GUI
      Wizard.CreateDialog

      Wizard.SetContents(
        # dialog caption
        _("Add-On Products"),
        # busy message (dialog)
        VBox(Label(_("Initializing..."))),
        # help
        _("<p>Initializing add-on products...</p>"),
        false,
        false
      )

      Wizard.SetDesktopTitleAndIcon("org.opensuse.yast.AddOn")

      Wizard.DisableBackButton
      Wizard.DisableAbortButton
      Wizard.DisableNextButton

      # --> Initialization start

      # check whether running as root
      # and having the packager for ourselves
      if !Confirm.MustBeRoot || !PackageLock.Check
        UI.CloseDialog
        return :abort
      end

      # initialize target to import all trusted keys (#165849)
      Pkg.TargetInitialize("/")
      Pkg.TargetLoad

      PackageCallbacks.InitPackageCallbacks

      # Initialize current sources
      Read()
      # <-- Initialization finish

      Wizard.EnableAbortButton
      Wizard.EnableNextButton

      ret = RunAddOnsOverviewDialog()

      Pkg.SourceSaveAll if @ret == :next

      # bugzilla #293428
      # Release all sources before adding a new one
      # because of CD/DVD + url cd://
      Pkg.SourceReleaseAll

      UI.CloseDialog
      ret
    end
  end
end

Yast::AddOnClient.new.main
