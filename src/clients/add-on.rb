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
      Yast.import "XML"

      Yast.include self, "add-on/add-on-workflow.rb"

      @wfm_args = WFM.Args
      Builtins.y2milestone("ARGS: %1", @wfm_args)

      @commands = CommandLine.Parse(@wfm_args)
      Builtins.y2debug("Commands: %1", @commands)

      # bnc #430852
      if Ops.get_string(@commands, "command", "") == "help" ||
          Ops.get_string(@commands, "command", "") == "longhelp"
        Mode.SetUI("commandline")
        # TRANSLATORS: commandline help
        CommandLine.Print(
          _(
            "\n" +
              "Add-on Module Help\n" +
              "------------------\n" +
              "\n" +
              "To add a new add-on product via the command-line, use this syntax:\n" +
              "    /sbin/yast2 add-on URL\n" +
              "URL is the path to the add-on source.\n" +
              "\n" +
              "Examples of URL:\n" +
              "http://server.name/directory/Lang-AddOn-10.2-i386/\n" +
              "ftp://server.name/directory/Lang-AddOn-10.2-i386/\n" +
              "nfs://server.name/directory/SDK1-SLE-i386/\n" +
              "disk://dev/sda5/directory/Product/CD1/\n" +
              "cd://\n" +
              "dvd://\n"
          )
        )
        return :auto
      elsif Ops.get_string(@commands, "command", "") == "xmlhelp"
        Mode.SetUI("commandline")
        if !Builtins.haskey(Ops.get_map(@commands, "options", {}), "xmlfile")
          CommandLine.Print(
            _(
              "Target file name ('xmlfile' option) is missing. Use xmlfile=<target_XML_file> command line option."
            )
          )
          return :auto
        else
          @doc = {}

          Ops.set(
            @doc,
            "listEntries",
            {
              "commands" => "command",
              "options"  => "option",
              "examples" => "example"
            }
          )
          Ops.set(
            @doc,
            "systemID",
            Ops.add(Directory.schemadir, "/commandline.dtd")
          )
          Ops.set(@doc, "typeNamespace", "http://www.suse.com/1.0/configns")
          Ops.set(@doc, "rootElement", "commandline")
          XML.xmlCreateDoc(:xmlhelp, @doc)

          @exportmap = { "module" => "add-on" }
          XML.YCPToXMLFile(
            :xmlhelp,
            @exportmap,
            Ops.get_string(@commands, ["options", "xmlfile"], "")
          )
          Builtins.y2milestone("exported XML map: %1", @exportmap)
          return :auto
        end
      end

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

      Wizard.SetDesktopTitleAndIcon("org.openSUSE.YaST.AddOn")

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
      @ret = nil

      # <-- Initialization finish

      Wizard.EnableAbortButton
      Wizard.EnableNextButton

      if Builtins.size(WFM.Args) == 0
        Builtins.y2milestone(
          "Url not specified in cmdline, starting full-featured module"
        )
        @ret = RunAddOnsOverviewDialog()
      else
        @url = Convert.to_string(WFM.Args(0))
        Builtins.y2milestone("Specified URL %1", @url)
        begin
          @createResult = SourceManager.createSource(@url)
          Builtins.y2milestone("Source creating result: %1", @createResult)
        end while @createResult == :again
        AddOnProduct.last_ret = :next
        @ret = RunAutorunWizard()
      end

      Pkg.SourceSaveAll if @ret == :next

      # bugzilla #293428
      # Release all sources before adding a new one
      # because of CD/DVD + url cd://
      Pkg.SourceReleaseAll

      UI.CloseDialog
      @ret 

      # EOF
    end
  end
end

Yast::AddOnClient.new.main
