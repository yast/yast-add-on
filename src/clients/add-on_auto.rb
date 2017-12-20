# encoding: utf-8

# File:
#      add-on_auto.ycp
#
# Module:
#      Add-On autoinstallation and configuration
#
# Summary:
#      Add-On autoinstallation preparation
#
# Authors:
#      Jiri Srain <jsrain@suse.cz>
#
# $Id$
#
module Yast
  class AddOnAutoClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "add-on"

      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("add-on auto started")

      Yast.import "AddOnProduct"
      Yast.import "Progress"
      Yast.import "AutoinstSoftware"
      Yast.import "PackageCallbacks"
      Yast.import "Label"
      Yast.import "AutoinstGeneral"
      Yast.import "PackageLock"
      Yast.import "Installation"
      Yast.import "String"

      Yast.include self, "add-on/add-on-workflow.rb"

      @progress_orig = Progress.set(false)


      @ret = nil
      @func = ""
      @param = {}

      # Check arguments
      if Ops.greater_than(Builtins.size(WFM.Args), 0) &&
          Ops.is_string?(WFM.Args(0))
        @func = Convert.to_string(WFM.Args(0))
        if Ops.greater_than(Builtins.size(WFM.Args), 1) &&
            Ops.is_map?(WFM.Args(1))
          @param = Convert.to_map(WFM.Args(1))
        end
      end
      Builtins.y2debug("func=%1", @func)
      Builtins.y2debug("param=%1", @param)

      if @func == "Import"
        @ret = AddOnProduct.Import(
          Convert.convert(@param, :from => "map", :to => "map <string, any>")
        )
      # Create a summary
      # return string
      elsif @func == "Summary"
        @ret = "<ul>\n"
        Builtins.foreach(AddOnProduct.add_on_products) do |prod|
          @ret = Ops.add(
            Convert.to_string(@ret),
            Builtins.sformat(
              _("<li>Media: %1, Path: %2, Product: %3</li>\n"),
              Ops.get_string(prod, "media_url", ""),
              Ops.get_string(prod, "product_dir", "/"),
              Ops.get_string(prod, "product", "")
            )
          )
        end
        @ret = Ops.add(Convert.to_string(@ret), "</ul>")
      # did configuration changed
      # return boolean
      elsif @func == "GetModified"
        @ret = AddOnProduct.modified
      # set configuration as changed
      # return boolean
      elsif @func == "SetModified"
        AddOnProduct.modified = true
        @ret = true
      # Reset configuration
      # return map or list
      elsif @func == "Reset"
        AddOnProduct.add_on_products = []
        @ret = {}
      # Change configuration
      # return symbol (i.e. `finish || `accept || `next || `cancel || `abort)
      elsif @func == "Change"
        Wizard.CreateDialog
        AutoinstSoftware.pmInit
        PackageCallbacks.InitPackageCallbacks
        @ret = RunAddOnMainDialog(
          false,
          true,
          true,
          Label.BackButton,
          Label.OKButton,
          Label.CancelButton,
          false
        )
        UI.CloseDialog
        return deep_copy(@ret)
      # Return configuration data
      # return map or list
      elsif @func == "Export"
        @ret = AddOnProduct.Export
      # Write configuration data
      # return boolean
      #
      #
      # **Structure:**
      #
      #
      #      <add-on>
      #     	<add_on_products config:type="list">
      #     		<listentry>
      #     			<media_url>http://software.opensuse.org/download/server:/dns/SLE_10/</media_url>
      #     			<product>buildservice</product>
      #     			<product_dir>/</product_dir>
      #     			<!-- (optional) -->
      #     			<name>User-Defined Product Name</name>
      #     			<signature-handling>
      #     				<accept_unsigned_file config:type="boolean">true</accept_unsigned_file>
      #     				<accept_file_without_checksum config:type="boolean">true</accept_file_without_checksum>
      #     				<accept_verification_failed config:type="boolean">true</accept_verification_failed>
      #     				<accept_unknown_gpg_key>
      #     					<all config:type="boolean">true</all>
      #     					<keys config:type="list">
      #     						<keyid>...</keyid>
      #     						<keyid>3B3011B76B9D6523</keyid>
      #     					</keys>
      #     				</accept_unknown_gpg_key>
      #     				<accept_non_trusted_gpg_key>
      #     				<all config:type="boolean">true</all>
      #     					<keys config:type="list">
      #     						<keyid>...</keyid>
      #     					</keys>
      #     				</accept_non_trusted_gpg_key>
      #     				<import_gpg_key>
      #     					<all config:type="boolean">true</all>
      #     					<keys config:type="list">
      #     						<keyid>...</keyid>
      #     					</keys>
      #     				</import_gpg_key>
      #     			</signature-handling>
      #     		</listentry>
      #     	</add_on_products>
      #      </add-on>
      #
      elsif @func == "Write"
        @sources = {}

        AddOnProduct.add_on_products.each do |prod|
          media = Ops.get_string(prod, "media_url", "")
          pth = Ops.get_string(prod, "product_dir", "/")
          if String.StartsWith(media, "relurl://")
            base = AddOnProduct.GetBaseProductURL
            media = AddOnProduct.GetAbsoluteURL(base, media)
            Builtins.y2milestone("relurl changed to %1", media)
          end
          Ops.set(@sources, media, Ops.get(@sources, media, {}))
          # set addon specific sig-handling
          AddOnProduct.SetSignatureCallbacks(
            Ops.get_string(prod, "product", "")
          )
          srcid = -1
          begin
            url = AddOnProduct.SetRepoUrlAlias(
              # Expanding URL in order to "translate" tags like $releasever
              Pkg.ExpandedUrl(media),
              Ops.get_string(prod, "alias", ""),
              Ops.get_string(prod, "name", "")
            )

            srcid = Pkg.SourceCreate(url, pth)

            if (srcid == -1 || srcid == nil)
              # revert back to the unexpanded URL to have the original URL
              # in the saved /etc/zypp/repos.d file
              Pkg.SourceChangeUrl(srcid, media)

              if Ops.get_boolean(prod, "ask_on_error", false)
                prod["ask_on_error"] = Popup.ContinueCancel(
                  Builtins.sformat(
                    _("Make the add-on \"%1\" available via \"%2\"."),
                    Ops.get_string(prod, "product", ""),
                    media
                  )
                )
              else
                # just report an error
                error_string = format(_("Failed to add product \"%s\" via\n%s\n"),
                  prod["product"], media)
                error_string << _("Please check logfiles for more information.")
                Report.Error(error_string)
              end
            elsif Ops.get_boolean(prod, "confirm_license", false)
              accepted = AddOnProduct.AcceptedLicenseAndInfoFile( srcid )
              if accepted == false
                Builtins.y2warning("License not accepted, delete the repository and halt the system")
                Pkg.SourceDelete(srcid)
                SCR.Execute(path(".target.bash"), "/sbin/halt -f -n -p")
              end
            end

            Ops.set(@sources, [media, pth], srcid)
            Builtins.y2milestone("New source ID: %1", srcid)

            # bugzilla #260613
            AddOnProduct.Integrate(srcid) if srcid != -1

          end while Ops.get(@sources, [media, pth], -1) == -1 &&
            Ops.get_boolean(prod, "ask_on_error", false) == true
          Ops.set(prod, "media", Ops.get(@sources, [media, pth], -1))
          # Adjust "name", bnc #434708
          if srcid != nil && srcid != -1
            repos = Pkg.SourceEditGet

            found_at = -1
            counter = -1

            Builtins.foreach(repos) do |one_repo|
              counter = Ops.add(counter, 1)
              if Ops.get_integer(one_repo, "SrcId", -1) == srcid
                found_at = counter
                raise Break
              end
            end

            if found_at != -1
              name = Ops.get_string(repos, [found_at, "name"], "")

              # Possibility to set name in control file, bnc #433981
              if Builtins.haskey(prod, "name")
                name = Ops.get_string(prod, "name", "")
                Builtins.y2milestone("Preferred name: %1", name)
                # Or use the one returned by Pkg::RepositoryScan
              else
                repos_at_url = Pkg.RepositoryScan(Pkg.ExpandedUrl(media))
                # [ ["Product Name", "Path" ] ]
                Builtins.foreach(repos_at_url) do |one_repo|
                  if Ops.get(one_repo, 1, "") == pth
                    name = Ops.get(one_repo, 0, "")
                    raise Break
                  end
                end
                Builtins.y2milestone("Preferred name: %1", name)
              end

              Ops.set(repos, [found_at, "name"], name)
              Pkg.SourceEditSet(repos)
            end
          end
          if Ops.get_string(prod, "product", "") != ""
            Builtins.y2milestone(
              "Installing product: %1",
              Ops.get_string(prod, "product", "")
            )
            Pkg.ResolvableInstall(Ops.get_string(prod, "product", ""), :product)
          else
            Builtins.y2warning("No product to install")
          end
        end

        # reread agents, redraw wizard steps, etc.
        AddOnProduct.ReIntegrateFromScratch

        @ret = true
      # Reads configuration of add-ons from the current system
      # to memory. To get that configuration, use Export() functionality.
      #
      # @return [Boolean]
      elsif @func == "Read"
        if !PackageLock.Check
          Builtins.y2error("Cannot get package lock")
          return false
        end
        Builtins.y2milestone("Reseting Pkg")
        Pkg.PkgApplReset
        Pkg.PkgReset

        Pkg.TargetInitialize(Installation.destdir)
        Pkg.TargetLoad
        Pkg.SourceStartManager(true)
        Pkg.PkgSolve(true)

        @ret = ReadFromSystem()
      else
        Builtins.y2error("unknown function: %1", @func)
        @ret = false
      end
      Progress.set(@progress_orig)

      Builtins.y2debug("ret=%1", @ret)
      Builtins.y2milestone("add-on_auto finished")
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret)

      # EOF
    end
  end
end

Yast::AddOnAutoClient.new.main
