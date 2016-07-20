# encoding: utf-8

# File:
#      include/add-on/add-on-workflow.ycp
#
# Module:
#      System installation
#
# Summary:
#      Add-on product installation workflow
#
# Authors:
#      Jiri Srain <jsrain@suse.cz>
#	Lukas Ocilka <locilka@suse.cz>
#
#
module Yast
  module AddOnAddOnWorkflowInclude
    include Yast::Logger

    def initialize_add_on_add_on_workflow(include_target)
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "add-on"

      Yast.import "AddOnProduct"
      Yast.import "WorkflowManager"
      Yast.import "Linuxrc"
      Yast.import "Mode"
      Yast.import "Popup"
      Yast.import "Report"
      Yast.import "Sequencer"
      Yast.import "SourceManager"
      Yast.import "PackageSystem"
      Yast.import "ProductProfile"
      Yast.import "SuSEFirewall"
      Yast.import "Stage"
      Yast.import "Wizard"
      Yast.import "Confirm"
      Yast.import "GetInstArgs"
      Yast.import "Installation"
      Yast.import "PackageCallbacks"
      Yast.import "PackagesUI"
      Yast.import "Packages"

      Yast.include include_target, "packager/inst_source_dialogs.rb"
      Yast.include include_target, "packager/repositories_include.rb"
      Yast.include include_target, "add-on/misc.rb"

      # Used for adding sources
      @createResult = :again

      @new_addon_name = ""

      @product_infos = {}
    end

    # Initialize current inst. sources
    def Read
      Pkg.SourceStartManager(true)
      :next
    end

    # Write (changed) inst. sources
    def Write
      Pkg.SourceSaveAll
      :next
    end

    # Checks whether some network is available in the current moment,
    # see the bug #170147 for more information.
    def IsAnyNetworkAvailable
      ret = false

      command = "TERM=dumb /sbin/ip -o address show | grep inet | grep -v scope.host"
      Builtins.y2milestone("Running %1", command)
      cmd_run = Convert.to_map(
        SCR.Execute(path(".target.bash_output"), command)
      )
      Builtins.y2milestone("Command returned: %1", cmd_run)

      # command failed
      if Ops.get_integer(cmd_run, "exit", -1) != 0
        # some errors were there, we don't know the status, rather return that it's available
        # `grep` also returns non zero exit code when there is nothing to do...
        if Ops.get_string(cmd_run, "stdout", "") != ""
          Builtins.y2error("Checking the network failed")
          ret = true
        end
        # some devices are listed
      elsif Ops.get_string(cmd_run, "stdout", "") != nil &&
          Ops.get_string(cmd_run, "stdout", "") != "" &&
          Ops.get_string(cmd_run, "stdout", "") != "\n"
        ret = true
      end

      ret
    end

    # Returns begining string for source type
    #
    # @param [Symbol] source_type
    # @return [String] url begins with...
    def GetURLBeginsWith(source_type)
      url = ""

      if source_type == :ftp
        url = "ftp://"
      elsif source_type == :http
        url = "http://"
      elsif source_type == :https
        url = "https://"
      elsif source_type == :samba
        url = "smb://"
      elsif source_type == :nfs
        url = "nfs://"
      elsif source_type == :cd
        url = "cd:///"
      elsif source_type == :dvd
        url = "dvd:///"
      elsif source_type == :local_dir
        url = "dir://"
      end

      url
    end

    # used Add-Ons are stored in AddOnProduct::add_on_products
    # bnc #393620
    def AddAddOnToStore(src_id)
      if src_id == nil
        Builtins.y2error("Wrong src_id: %1", src_id)
        return
      end

      # BNC #450274
      # Prevent from adding one product twice
      matching_products = Builtins.filter(AddOnProduct.add_on_products) do |one_product|
        Ops.get_integer(one_product, "media", -1) == src_id
      end

      if Ops.greater_than(Builtins.size(matching_products), 0)
        Builtins.y2milestone("Product already added: %1", matching_products)
        return
      end

      source_data = Pkg.SourceGeneralData(src_id)

      AddOnProduct.add_on_products = Builtins.add(
        AddOnProduct.add_on_products,
        {
          "media"       => AddOnProduct.src_id,
          # table cell
          "product"     => Ops.get_locale(
            source_data,
            "name",
            Ops.get_locale(
              source_data,
              "alias",
              _("No product found in the repository.")
            )
          ),
          "media_url"   => Ops.get_string(source_data, "url", ""),
          "product_dir" => Ops.get_string(source_data, "product_dir", "")
        }
      )

      nil
    end

    # Run dialog for selecting the media
    # @return [Symbol] for wizard sequencer
    def MediaSelect
      aliases = {
        "type"  => lambda do
          ret = TypeDialog()
          log.debug "SourceDialogs.addon_enabled: #{SourceDialogs.addon_enabled}"
          # explicitly check for false (nil means the checkbox was not displayed)
          ret = :skip if ret == :next && SourceDialogs.addon_enabled == false
          log.debug "TypeDialog result: #{ret}"
          ret
        end,
        "edit"  => lambda { EditDialog() },
        "store" => lambda do
          StoreSource()
        end
      }

      sources_before = Pkg.SourceGetCurrent(false)
      Builtins.y2milestone("Sources before adding new one: %1", sources_before)

      sequence = {
        "ws_start" => "type",
        "type"     => {
          :next   => "edit",
          # bnc #392083
          :finish => "store",
          :abort  => :abort,
          :skip   => :skip
        },
        "edit"     => {
          :next   => "store",
          # bnc #392083
          :finish => "store",
          :abort  => :abort
        },
        "store"    => {
          :next   => :next,
          # bnc #392083
          :finish => :next,
          :abort  => :abort
        }
      }

      Builtins.y2milestone("Starting repository sequence")
      ret = Sequencer.Run(aliases, sequence)
      log.info "Repository sequence result: #{ret}"

      if ret == :next
        sources_after = Pkg.SourceGetCurrent(false)
        Builtins.y2milestone("Sources with new one added: %1", sources_after)

        # bnc #393011
        # AddOnProduct::src_id must be set to the latest source ID
        src_id_found = false

        Builtins.foreach(sources_after) do |one_source|
          if !Builtins.contains(sources_before, one_source)
            AddOnProduct.src_id = one_source
            Builtins.y2milestone("Added source ID is: %1", AddOnProduct.src_id)
            src_id_found = true
            raise Break
          end
        end

        if src_id_found
          # BNC #481828: Using LABEL from content file as a repository name
          Packages.AdjustSourcePropertiesAccordingToProduct(AddOnProduct.src_id)
          # used add-ons are stored in a special list
          AddAddOnToStore(AddOnProduct.src_id)
        else
          AddOnProduct.src_id = Ops.get(
            sources_after,
            Ops.subtract(Builtins.size(sources_after), 1),
            0
          )
          Builtins.y2warning("Fallback src_id: %1", AddOnProduct.src_id)
        end

        # BNC #441380
        # Refresh and load the added source, this is needed since the unified
        # functions from packager are used.
        Pkg.SourceRefreshNow(AddOnProduct.src_id)
        Pkg.SourceLoad

        # BNC #468449
        # It may happen that the add-on control file contains some code that
        # would drop the changes made, so it's better to save the soruces now
        if Mode.normal
          Builtins.y2milestone("Saving all sources")
          Pkg.SourceSaveAll
        end
      end

      AddOnProduct.last_ret = ret
      Builtins.y2milestone("MediaSelect Dialog ret: %1", ret)
      ret
    end

    # bugzilla #304659
    # Sets the Add-On's product name
    #
    # @param [Fixnum] src_id (source ID)
    def SetAddOnProductName(src_id)
      @new_addon_name = ""

      if src_id == nil
        Builtins.y2error("Cannot set name, no ID!")
        return
      end

      @new_addon_name = SourceDialogs.GetRepoName

      # no name to change to
      if @new_addon_name == nil || @new_addon_name == ""
        Builtins.y2milestone("No special name set")
        return
      end

      new_addon_set = [{ "SrcId" => src_id, "name" => @new_addon_name }]
      result = Pkg.SourceEditSet(new_addon_set)

      Builtins.y2milestone(
        "Adjusting Add-On: %1 returned: %2",
        new_addon_set,
        result
      )

      # do not use it next time
      SourceDialogs.SetRepoName("")

      nil
    end

    # Run dialog for selecting the catalog on the media (if more than one present)
    # @return [Symbol] for wizard sequencer
    def CatalogSelect
      sources = deep_copy(SourceManager.newSources)
      Builtins.y2milestone("New sources: %1", sources)

      if Builtins.size(sources) == 0
        # error report
        Report.Error(_("No software repository found on medium."))
        Builtins.y2milestone("CatalogSelect Dialog ret: %1", :back)
        return :back
      end

      if Builtins.size(sources) == 1
        if AddOnProduct.last_ret != :next
          Builtins.y2milestone("Deleting source %1", Ops.get(sources, 0, 0))
          Pkg.SourceDelete(Ops.get(sources, 0, 0))

          Builtins.y2milestone(
            "CatalogSelect Dialog ret: %1",
            AddOnProduct.last_ret
          )
          return AddOnProduct.last_ret
        end

        # busy message
        UI.OpenDialog(
          Label(Id(:add_on_popup_id), _("Initializing new source..."))
        )
        src_id = Ops.get(SourceManager.newSources, 0, 0)

        # BNC #481828: Using LABEL from content file as a repository name
        Packages.AdjustSourcePropertiesAccordingToProduct(src_id)

        # a little hack because of packager leaving
        # windows open...
        if UI.WidgetExists(:add_on_popup_id)
          UI.CloseDialog
        elsif UI.WidgetExists(:contents)
          Builtins.y2warning("Already in base dialog!")
        else
          Builtins.y2error("Error in packager, closing current dialog!")
          while !UI.WidgetExists(:contents)
            Builtins.y2milestone("Calling UI::CloseDialog")
            UI.CloseDialog
          end
        end

        AddOnProduct.src_id = src_id
        SourceManager.newSources = [src_id]
        Builtins.y2milestone("Only one source available - skipping dialog")

        Builtins.y2milestone(
          "CatalogSelect Dialog ret: %1",
          AddOnProduct.last_ret
        )
        return AddOnProduct.last_ret
      end

      Builtins.y2milestone("Running catalog select dialog")
      catalogs = Builtins.maplist(sources) do |src|
        data = Pkg.SourceGeneralData(src)
        # placeholder for unknown directory
        dir = Ops.get_locale(data, "product_dir", _("Unknown"))
        dir = "/" if dir == ""
        Item(
          Id(src),
          Builtins.sformat(
            _("URL: %1, Directory: %2"),
            Ops.get_locale(
              # place holder for unknown URL
              data,
              "url",
              _("Unknown")
            ),
            dir
          )
        )
      end

      # dialog caption
      title = _("Software Repository Selection")
      # help text
      help_text = _(
        "<p><big><b>Software Repository Selection</b></big><br>\n" +
          "Multiple repositories were found on the selected medium.\n" +
          "Select the repository to use.</p>\n"
      )

      contents = HBox(
        HSpacing(4),
        VBox(
          VSpacing(2),
          SelectionBox(Id(:catalogs), _("Repositories &Found"), catalogs),
          VSpacing(2)
        ),
        HSpacing(4)
      )
      Wizard.SetContents(title, contents, help_text, true, true)
      ret = nil
      selected = nil
      while ret == nil
        ret = Convert.to_symbol(UI.UserInput)
        if ret == :abort || ret == :cancel
          ret = :abort
          break if Popup.YesNo(_("Really abort add-on product installation?"))
          next
        elsif ret == :back
          break
        elsif ret == :next
          selected = Convert.to_integer(
            UI.QueryWidget(Id(:catalogs), :CurrentItem)
          )
          if selected == nil
            ret = nil
            # popup message
            Popup.Message(_("Select a repository."))
          end
        end
      end

      if ret != :next
        Builtins.foreach(SourceManager.newSources) do |src|
          Builtins.y2milestone("Deleting source %1", src)
          Pkg.SourceDelete(src)
        end
      else
        Builtins.foreach(SourceManager.newSources) do |src|
          if src != selected
            Builtins.y2milestone("Deleting unused source %1", src)
            Pkg.SourceDelete(src)
          end
        end

        # BNC #481828: Using LABEL from content file as a repository name
        Packages.AdjustSourcePropertiesAccordingToProduct(selected)

        AddOnProduct.src_id = selected
        SourceManager.newSources = [selected]
      end

      AddOnProduct.last_ret = ret
      Builtins.y2milestone(
        "CatalogSelect Dialog ret: %1",
        AddOnProduct.last_ret
      )
      ret
    end

    # BNC #474745
    # Installs all the products from just added add-on media
    def InstallProduct
      Builtins.y2milestone("AddOnID: %1", AddOnProduct.src_id)

      if AddOnProduct.src_id == nil || Ops.less_than(AddOnProduct.src_id, 0)
        Builtins.y2error("No source has been added")
        return :next
      end

      all_products = Pkg.ResolvableProperties("", :product, "")

      # `selected and `installed products
      # each map contains "name" and "version"
      s_a_i_products = []

      Builtins.foreach(all_products) do |one_product|
        s_a_i_products = Builtins.add(
          s_a_i_products,
          {
            "name"    => Ops.get_string(one_product, "name", "xyz"),
            "version" => Ops.get_string(one_product, "version", "abc")
          }
        )
      end

      Builtins.foreach(all_products) do |one_product|
        #	map this_product = $["name":one_product["name"]:"zyx", "version":one_product["version"]:"cba"];

        # Product doesn't match the new source ID
        if Ops.get_integer(one_product, "source", -255) != AddOnProduct.src_id
          next
        end
        # Product is not available (either `installed or `selected or ...)
        next if Ops.get_symbol(one_product, "status", :available) != :available
        #	// Available but also already installed or selected
        #	if (contains (s_a_i_products, this_product)) {
        #	    y2warning ("Product %1 is already installed", this_product);
        #	    return;
        #	}
        product_name = Ops.get_string(one_product, "name", "-Unknown-Product-")
        Builtins.y2milestone(
          "Selecting product '%1' for installation -> %2",
          product_name,
          Pkg.ResolvableInstall(product_name, :product)
        )
      end

      :next
    end

    def ProductSelect
      all_products = Pkg.ResolvableProperties("", :product, "")

      already_used_urls = {}
      # getting all source urls and product_dirs
      Builtins.foreach(all_products) do |p|
        one_src_id = Builtins.tointeger(Ops.get(p, "source"))
        next if one_src_id == nil
        # the last source (just added)
        next if one_src_id == AddOnProduct.src_id
        src_general_data = Pkg.SourceGeneralData(one_src_id)
        source_url = Ops.get_string(src_general_data, "url", "")
        if source_url != "" && source_url != nil
          Ops.set(
            already_used_urls,
            source_url,
            Ops.get_string(src_general_data, "product_dir", "")
          )
        end
      end
      Builtins.y2milestone(
        "Already used urls with product_dirs: %1",
        already_used_urls
      )

      installed_products = Builtins.filter(all_products) do |p|
        Ops.get(p, "status") == :selected || Ops.get(p, "status") == :installed
      end
      Builtins.y2milestone(
        "Already installed/selected products: %1",
        installed_products
      )
      products = Builtins.filter(all_products) do |p|
        Ops.get_integer(p, "source", -1) == AddOnProduct.src_id
      end
      Builtins.y2milestone("Products on the media: %1", products)

      # there are no product on the given url
      if Builtins.size(products) == 0
        Builtins.y2milestone(
          "No poduct found on the media, but anyway, using it :-)"
        )
        # Display /media.1/info.txt if such file exists
        # Display license and wait for agreement
        # FIXME the same code is below
        license_ret2 = AddOnProduct.AcceptedLicenseAndInfoFile(
          AddOnProduct.src_id
        )
        if license_ret2 != true
          Builtins.y2milestone(
            "Removing the current source ID %1",
            AddOnProduct.src_id
          )
          Pkg.SourceDelete(AddOnProduct.src_id)

          Builtins.y2milestone("ProductSelect Dialog ret: %1", :abort)
          return :abort
        end

        data = Pkg.SourceGeneralData(AddOnProduct.src_id)
        url = Ops.get_string(data, "url", "")
        product_dir = Ops.get_string(data, "product_dir", "")

        # bugzilla #304659
        SetAddOnProductName(AddOnProduct.src_id)

        AddOnProduct.add_on_products = Builtins.add(
          AddOnProduct.add_on_products,
          {
            "media"       => AddOnProduct.src_id,
            # table cell
            "product"     => @new_addon_name != "" &&
              @new_addon_name != nil ?
              @new_addon_name :
              _("No product found in the repository."),
            "media_url"   => url,
            "product_dir" => product_dir
          }
        )

        if Mode.config
          AddOnProduct.mode_config_sources = Builtins.add(
            AddOnProduct.mode_config_sources,
            AddOnProduct.src_id
          )
        end

        Builtins.y2milestone("ProductSelect Dialog ret: %1", :next)
        return :next
      end

      # Display /media.1/info.txt if such file exists
      # Display license and wait for agreement
      # FIXME the same code is above
      license_ret = AddOnProduct.AcceptedLicenseAndInfoFile(AddOnProduct.src_id)
      if license_ret != true
        Builtins.y2milestone(
          "Removing the current source ID %1",
          AddOnProduct.src_id
        )
        Pkg.SourceDelete(AddOnProduct.src_id)

        Builtins.y2milestone("ProductSelect Dialog ret: %1", :abort)
        return :abort
      end

      # there is only one product on the given url
      if Builtins.size(products) == 1
        # bugzilla #227605
        # this product with this url has been already installed or selected for installation
        src_general_data = Pkg.SourceGeneralData(AddOnProduct.src_id)
        current_url = Ops.get_string(src_general_data, "url", "")

        Builtins.y2milestone("Only one product available - skipping dialog")
        prod = Ops.get(products, 0, {})
        if !AddOnProduct.CheckProductDependencies(
            [Ops.get_string(prod, "name", "")]
          )
          Pkg.ResolvableRemove(Ops.get_string(prod, "name", ""), :product)
          # message popup
          Popup.Message(
            _("Dependencies of the add-on product cannot be fulfilled.")
          )
          AddOnProduct.last_ret = :back

          Builtins.y2milestone("ProductSelect Dialog ret: %1", :back)
          return :back
        end
        # check whether the product is already available on some media - it is similar as below
        found_source = -1
        Builtins.foreach(all_products) do |p|
          if Ops.get_string(p, "name", "") == Ops.get_string(prod, "name", "") &&
              Ops.get_string(p, "version", "") ==
                Ops.get_string(prod, "version", "") &&
              Ops.get_integer(p, "media", -2) !=
                Ops.get_integer(prod, "media", -3)
            Builtins.y2milestone(
              "Product %1 already available on media %2",
              p,
              Ops.get_integer(p, "media", -1)
            )
            found_source = Ops.get_integer(p, "media", -1)
            raise Break
          end
        end
        if found_source != -1
          Builtins.y2milestone("Deleting source %1", AddOnProduct.src_id)
          Pkg.SourceDelete(AddOnProduct.src_id)
          AddOnProduct.src_id = found_source
        end
        Pkg.ResolvableInstall(Ops.get_string(prod, "name", ""), :product)
        data = Pkg.SourceGeneralData(AddOnProduct.src_id)

        url = Ops.get_string(data, "url", "")
        product_dir = Ops.get_string(data, "product_dir", "")

        # bugzilla #304659
        SetAddOnProductName(AddOnProduct.src_id)

        AddOnProduct.add_on_products = Builtins.add(
          AddOnProduct.add_on_products,
          {
            "media"            => AddOnProduct.src_id,
            "product"          => @new_addon_name != "" &&
              @new_addon_name != nil ?
              @new_addon_name :
              Ops.get_string(
                prod,
                "display_name",
                Ops.get_string(
                  prod,
                  "short_name",
                  Ops.get_string(prod, "name", "")
                )
              ),
            "autoyast_product" => Ops.get_string(prod, "name", ""),
            "media_url"        => url,
            "product_dir"      => product_dir
          }
        )

        if found_source == -1 && Mode.config
          AddOnProduct.mode_config_sources = Builtins.add(
            AddOnProduct.mode_config_sources,
            AddOnProduct.src_id
          )
        end

        Builtins.y2milestone("ProductSelect Dialog ret: %1", :next)
        return :next
      end

      # there are more than one products on the given url
      Builtins.y2milestone("Running product selection dialog")
      ret = nil
      items = Builtins.maplist(products) do |product|
        Item(
          Id(Ops.get_string(product, "name", "")),
          Ops.get_string(product, "name", "")
        )
      end
      # dialog caption
      title = _("Product Selection")
      contents = HBox(
        HStretch(),
        VBox(
          VStretch(),
          # multi selection list
          MultiSelectionBox(Id(:products), _("Available Products"), items),
          VStretch()
        ),
        HStretch()
      )
      # help text
      help_text = _(
        "<p><b><big>Product Selection</big></b><br/>\n" +
          "Multiple products were found in the repository. Select the products\n" +
          "to install.</p>\n"
      )
      Wizard.SetContents(title, contents, help_text, true, true)
      while ret == nil
        ret = Convert.to_symbol(UI.UserInput)
        if ret == :cancel || ret == :abort
          ret = :abort
          #	    if (Stage::initial())
          #	    {
          #	        if (Popup::ConfirmAbort (`painless))
          #		    break;
          #	    }
          #	    else
          #	    {
          # yes-no popup
          break if Popup.YesNo(_("Really abort add-on product installation?"))
          #	    }
          next
        end
        if ret == :next
          selected = Convert.convert(
            UI.QueryWidget(Id(:products), :SelectedItems),
            :from => "any",
            :to   => "list <string>"
          )
          # check whether the product is already available on some media - it is similar as above
          prods = Builtins.filter(products) do |p|
            Builtins.contains(selected, Ops.get_string(p, "name", ""))
          end
          all_found = true
          prod2src = {}
          Builtins.foreach(prods) do |prod|
            product_found = false
            Builtins.foreach(all_products) do |p|
              if Ops.get_string(p, "name", "") ==
                  Ops.get_string(prod, "name", "") &&
                  Ops.get_string(p, "version", "") ==
                    Ops.get_string(prod, "version", "") &&
                  Ops.get_integer(p, "media", -2) !=
                    Ops.get_integer(prod, "media", -3)
                product_found = true
                Ops.set(
                  prod2src,
                  Ops.get_string(prod, "name", ""),
                  Ops.get_integer(p, "media", -3)
                )
                raise Break
              end
            end
            all_found = all_found && product_found
          end
          if all_found
            Builtins.y2milestone("Deleting source %1", AddOnProduct.src_id)
            Pkg.SourceDelete(AddOnProduct.src_id)
            AddOnProduct.src_id = -1
          end
          Builtins.foreach(selected) do |product|
            Pkg.ResolvableInstall(product, :product)
          end
          if !AddOnProduct.CheckProductDependencies(selected)
            Builtins.foreach(selected) do |product|
              Pkg.ResolvableRemove(product, :product)
            end
            # message popup
            Popup.Message(
              _(
                "Dependencies of the selected add-on products cannot be fulfilled."
              )
            )
            ret = nil
            next
          end
          data = Pkg.SourceGeneralData(AddOnProduct.src_id)
          url = Ops.get_string(data, "url", "")
          product_dir = Ops.get_string(data, "product_dir", "")

          Builtins.foreach(selected) do |product|
            src_id = AddOnProduct.src_id == -1 ?
              Ops.get(prod2src, product, -1) :
              AddOnProduct.src_id
            # bugzilla #304659
            SetAddOnProductName(AddOnProduct.src_id)
            AddOnProduct.add_on_products = Builtins.add(
              AddOnProduct.add_on_products,
              {
                "media"             => src_id,
                "product"           => @new_addon_name != "" &&
                  @new_addon_name != nil ? @new_addon_name : product,
                "autoyast_prouduct" => product,
                "media_url"         => url,
                "product_dir"       => product_dir
              }
            )
          end
          if AddOnProduct.src_id != -1 && Mode.config
            AddOnProduct.mode_config_sources = Builtins.add(
              AddOnProduct.mode_config_sources,
              AddOnProduct.src_id
            )
          end
        elsif ret != :back
          ret = nil
        end
      end

      if ret == :abort
        Builtins.y2milestone("Deleting source %1", AddOnProduct.src_id)
        Pkg.SourceDelete(AddOnProduct.src_id)
      end

      AddOnProduct.last_ret = ret
      Builtins.y2milestone(
        "ProductSelect Dialog ret: %1",
        AddOnProduct.last_ret
      )
      ret
    end

    # Check new product compliance; may abort the installation
    def CheckCompliance
      if ProductProfile.CheckCompliance(AddOnProduct.src_id)
        return :next
      else
        return :abort
      end
    end

    def RunWizard
      aliases = {
        "media"            => lambda { MediaSelect() },
        "install_product"  => lambda { InstallProduct() },
        "check_compliance" => lambda { CheckCompliance() }
      }


      sequence = {
        "ws_start"        => "media",
        "media"           => {
          :abort  => :abort,
          :next   => "check_compliance",
          :finish => "check_compliance",
          :skip   => :skip
        },
        #	"catalog" : $[
        #	    `abort : `abort,
        #	    `next : "product",
        #	    `finish : `next,
        #	],
        #	"product" : $[
        #	    `abort : `abort,
        #	    `next : `next,
        #	    `finish : `next,
        #	],
        "check_compliance" => {
          :abort => :abort,
          :next  => "install_product"
        },
        "install_product" => {
          :abort  => :abort,
          :next   => :next,
          :finish => :next
        }
      }
      Sequencer.Run(aliases, sequence)
    end

    def RunAutorunWizard
      aliases = { "catalog" => lambda { CatalogSelect() }, "product" => lambda do
        ProductSelect()
      end }

      sequence = {
        "ws_start" => "catalog",
        "catalog"  => { :abort => :abort, :next => "product", :finish => :next },
        "product"  => { :abort => :abort, :next => :next, :finish => :next }
      }
      Sequencer.Run(aliases, sequence)
    end



    def Redraw(enable_back, enable_next, enable_abort, back_button, next_button, abort_button)
      Builtins.y2milestone("Called Redraw()")
      # main screen heading
      title = _("Add-On Product Installation")

      # Help for add-on products
      help = _(
        "<p><big><b>Add-On Product Installation</b></big><br/>\n" +
          "Here see all add-on products that are selected for installation.\n" +
          "To add a new product, click <b>Add</b>. To remove an already added one,\n" +
          "select it and click <b>Delete</b>.</p>"
      )

      Builtins.y2milestone("Current products: %1", AddOnProduct.add_on_products)

      index = -1
      items = Builtins.maplist(AddOnProduct.add_on_products) do |product|
        Builtins.y2milestone("%1", product)
        index = Ops.add(index, 1)
        data = {}
        # BNC #464162, In AytoYaST, there is no media nr. yet
        if Builtins.haskey(product, "media") &&
            Ops.greater_than(Ops.get_integer(product, "media", -1), -1)
          data = Pkg.SourceGeneralData(Ops.get_integer(product, "media", -1))
        else
          data = deep_copy(product)
          if Builtins.haskey(data, "media_url")
            Ops.set(data, "url", Ops.get_string(data, "media_url", ""))
          end
        end
        # placeholder for unknown path
        dir = Ops.get_locale(data, "product_dir", _("Unknown"))
        dir = "/" if dir == ""
        # table cell, %1 is URL, %2 is directory name
        media = Builtins.sformat(
          _("%1, Directory: %2"),
          Ops.get_locale(
            # placeholder for unknown URL
            data,
            "url",
            _("Unknown")
          ),
          dir
        )
        Item(
          Id(index),
          Ops.get_string(
            # sformat (_("Product %1"), product["product"]:"")
            product,
            "product",
            ""
          ),
          media
        )
      end

      contents = VBox(
        Table(
          Id(:summary),
          Header(
            # table header
            _("Product"),
            # table header
            _("Media")
          ),
          items
        ),
        Left(
          HBox(
            PushButton(Id(:add), Label.AddButton),
            PushButton(Id(:delete), Label.DeleteButton),
            HStretch()
          )
        )
      )

      Wizard.SetContentsButtons(title, contents, help, back_button, next_button)
      Wizard.SetAbortButton(:abort, abort_button)

      # Disable next button according to settings
      Wizard.DisableNextButton if !enable_next

      # If back or abort buttons should not be enabled, hide them
      # -> [Cancel] [OK] dialog
      Wizard.HideBackButton if !enable_back
      Wizard.HideAbortButton if !enable_abort

      Wizard.SetTitleIcon("yast-addon")

      # disable delete button if no items listed
      # bug #203809
      UI.ChangeWidget(Id(:delete), :Enabled, false) if Builtins.size(items) == 0

      nil
    end

    def RemoveSelectedAddOn(selected)
      Builtins.y2milestone(
        "Deleting %1 %2",
        selected,
        Ops.get(AddOnProduct.add_on_products, selected)
      )

      # remove whole media if the product is the only one on the media
      media = Ops.get_integer(
        AddOnProduct.add_on_products,
        [selected, "media"],
        -1
      )
      med_count = Builtins.size(Builtins.filter(AddOnProduct.add_on_products) do |prod|
        Ops.get_integer(prod, "media", -1) == media
      end)

      if med_count == 1
        Builtins.y2milestone("Deleting source %1", media)
        Pkg.SourceDelete(media)
      end

      # remove the selected record
      Ops.set(AddOnProduct.add_on_products, selected, nil)
      AddOnProduct.add_on_products = Builtins.filter(
        AddOnProduct.add_on_products
      ) { |prod| prod != nil }

      # Remove product from add-ons
      AddOnProduct.Disintegrate(media)

      # remove product from list of product to register (FATE #301312)
      AddOnProduct.RemoveRegistrationFlag(media)

      nil
    end



    # bugzilla #221377
    # the original control file is stored as /control.xml
    # the other (added) control files are under the
    # /tmp/$yast_tmp/control_files/ directory
    # as $srcid.xml files
    #
    # bugzilla #237297
    # in the installation workflow - back/ next buttons
    # in the installation proposal - cancel / accept buttons
    #
    # bugzilla #449773
    # added enable_abort, abort_button
    #
    def RunAddOnMainDialog(enable_back, enable_next, enable_abort, back_button, next_button, abort_button, confirm_abort)
      ret = nil

      not_enough_memory = Stage.initial && HasInsufficientMemory()
      no_addons = Builtins.size(AddOnProduct.add_on_products) == 0

      # bugzilla #239630
      # It might be dangerous to add more installation sources in installation
      # on machine with less memory
      # Do not report when some add-ons are already in use
      if not_enough_memory && !no_addons
        if !ContinueIfInsufficientMemory()
          # next time, it will be skipped too
          Installation.add_on_selected = false
          Installation.productsources_selected = false

          return :next
        end
      end

      # FATE #301928 - Saving one click
      # Bugzilla #893103 be consistent, so always when there is no add-on skip
      if no_addons
        Builtins.y2milestone("Skipping to media_select")
        ret = :skip_to_add
      end

      # Show Add-Ons table
      Redraw(
        enable_back,
        enable_next,
        enable_abort,
        back_button,
        next_button,
        abort_button
      )

      # store the initial settings, only once
      WorkflowManager.SetBaseWorkflow(false)

      # added / removed
      some_addon_changed = false
      begin
        # FATE #301928 - Saving one click
        ret = Convert.to_symbol(UI.UserInput) unless ret == :skip_to_add

        # aborting
        if ret == :abort || ret == :cancel
          # User should confirm that
          if confirm_abort == true
            if Popup.ConfirmAbort(:incomplete)
              ret = :abort
              break
            else
              ret = nil
            end
            # Running system
          else
            break
          end

          # removing add-on
        elsif ret == :delete
          selected = Convert.to_integer(
            UI.QueryWidget(Id(:summary), :CurrentItem)
          )
          if selected == nil
            # message report
            Report.Message(_("Select a product to delete."))
            next
          end

          # bugzilla #305802
          next if !Confirm.DeleteSelected

          # TRANSLATORS: busy message
          UI.OpenDialog(Label(_("Removing selected add-on...")))

          RemoveSelectedAddOn(selected)
          some_addon_changed = true

          UI.CloseDialog

          Redraw(
            enable_back,
            enable_next,
            enable_abort,
            back_button,
            next_button,
            abort_button
          )

          # adding new add-on
        elsif ret == :add || ret == :skip_to_add
          # show checkbox only first time in installation when there is no
          # other addons, so allow to quickly skip adding addons, otherwise
          # it make no sense as user explicitelly want add addon
          SourceDialogs.display_addon_checkbox = ret == :skip_to_add

          # bugzilla #293428
          # Release all sources before adding a new one
          # because of CD/DVD + url cd://
          Pkg.SourceReleaseAll

          # bugzilla #305788
          # Use new wizard window for adding new Add-On.
          # Do not use "Steps" dialog.
          Wizard.OpenLeftTitleNextBackDialog
          Wizard.SetTitleIcon("yast-addon")
          ret2 = RunWizard()
          Wizard.CloseDialog

          log.info "Subworkflow result: ret2: #{ret2}"

          if ret2 == :next
            # Add-On product has been added, integrate it (change workflow, use y2update)
            AddOnProduct.Integrate(AddOnProduct.src_id)

            # check whether it requests registration (FATE #301312)
            AddOnProduct.PrepareForRegistration(AddOnProduct.src_id)
            some_addon_changed = true
            # do not keep first_time, otherwise summary won't be shown during installation
            ret = nil if ret == :skip_to_add
          elsif ret2 == :abort || ret2 == :cancel
            Builtins.y2milestone("Add-on sequence aborted")

            if AddOnProduct.src_id != nil
              Builtins.y2milestone(
                "Removing add-on repository: %1",
                AddOnProduct.src_id
              )

              # remove the repository
              Pkg.SourceDelete(AddOnProduct.src_id)

              AddOnProduct.add_on_products = Builtins.filter(
                AddOnProduct.add_on_products
              ) do |add_on_product|
                Ops.get_integer(add_on_product, "media", -1) !=
                  AddOnProduct.src_id
              end
            end
            # properly return abort in installation
            ret = :abort if ret == :skip_to_add
          # extra handling for the global enable checkbox
          elsif ret == :skip_to_add
            ret = :back if ret2 == :back
            ret = :next if ret2 == :skip
          end

          Redraw(
            enable_back,
            enable_next,
            enable_abort,
            back_button,
            next_button,
            abort_button
          )

          # bugzilla #293428
          # Release all sources after adding a new one
          # because of CD/DVD + url cd://
          Pkg.SourceReleaseAll
        end
      end until [:next, :back, :abort].include?(ret)

      Builtins.y2milestone(
        "Ret: %1, Some Add-on Added/Removed: %2",
        ret,
        some_addon_changed
      )
      Builtins.y2milestone(
        "Registration will be requested: %1",
        AddOnProduct.ProcessRegistration
      )

      # First stage installation, #247892
      # installation, update or autoinstallation
      if Stage.initial
        # bugzilla #221377
        AddOnProduct.ReIntegrateFromScratch if some_addon_changed
      end

      # bugzilla #293428
      # Release all sources after all Add-Ons are added and merged
      Builtins.y2milestone("Releasing all sources...")
      Pkg.SourceReleaseAll

      # bugzilla #305788
      Wizard.RestoreBackButton
      Wizard.RestoreAbortButton
      Wizard.RestoreNextButton

      ret
    end

    # AddOnsOverviewDialog -->

    def CreateAddOnsOverviewDialog
      Builtins.y2milestone("Creating OverviewDialog")

      Wizard.SetContents(
        # TRANSLATORS: dialog caption
        _("Installed Add-on Products"),
        VBox(
          Table(
            Id("list_of_addons"),
            Opt(:notify, :immediate),
            Header(
              # TRANSLATORS: table header item
              _("Add-on Product"),
              # TRANSLATORS: table header item
              _("URL")
            ),
            []
          ),
          VSquash(
            # Rich text plus border
            MinHeight(6, RichText(Id("product_details"), ""))
          ),
          HBox(
            PushButton(Id(:add), Label.AddButton),
            HSpacing(1),
            PushButton(Id(:delete), Label.DeleteButton),
            HStretch(),
            # TRANSLATORS: push button
            PushButton(Id(:packager), _("Run &Software Manager..."))
          )
        ),
        # TRANSLATORS: dialog help adp/1
        _("<p>All add-on products installed on your system are displayed.</p>") +
          # TRANSLATORS: dialog help adp/2
          _(
            "<p>Click <b>Add</b> to add a new add-on product, or <b>Delete</b> to remove an add-on which is in use.</p>"
          ),
        false,
        true
      )

      Wizard.SetTitleIcon("yast-addon")

      Wizard.HideBackButton
      Wizard.SetAbortButton(:abort, Label.CancelButton)
      Wizard.SetNextButton(:next, Label.OKButton)

      # BNC #517919: Broken layout in some obscure cases
      # Fixing it...
      UI.RecalcLayout

      nil
    end

    def ReturnCurrentlySelectedProductInfo
      if !UI.WidgetExists(Id("list_of_addons"))
        Builtins.y2error("No such widget: %1", "list_of_addons")
        return nil
      end

      item_id = Convert.to_string(
        UI.QueryWidget(Id("list_of_addons"), :CurrentItem)
      )

      # no items
      return nil if item_id == nil

      if !Builtins.regexpmatch(item_id, "product_")
        Builtins.y2error("Wrong product ID '%1'", item_id)
        return nil
      end

      item_id = Builtins.substring(item_id, 8)

      Ops.get_map(@product_infos, item_id, {})
    end

    def AdjustInfoWidget
      pi = ReturnCurrentlySelectedProductInfo()
      if pi == nil || pi == {}
        UI.ChangeWidget(Id("product_details"), :Value, "")
        return
      end

      rt_description = Builtins.sformat(
        "<p>%1\n%2\n%3\n%4</p>",
        Builtins.sformat(
          _("<b>Vendor:</b> %1<br>"),
          Ops.get_locale(pi, ["product", "vendor"], _("Unknown vendor"))
        ),
        Builtins.sformat(
          _("<b>Version:</b> %1<br>"),
          Ops.get_locale(pi, ["product", "version"], _("Unknown version"))
        ),
        Builtins.sformat(
          _("<b>Repository URL:</b> %1<br>"),
          Ops.greater_than(
            Builtins.size(Ops.get_list(pi, ["info", "URLs"], [])),
            0
          ) ?
            Builtins.mergestring(Ops.get_list(pi, ["info", "URLs"], []), ",") :
            _("Unknown repository URL")
        ),
        Ops.greater_than(
          Builtins.size(Ops.get_list(pi, ["info", "aliases"], [])),
          0
        ) ?
          Builtins.sformat(
            _("<b>Repository Alias:</b> %1<br>"),
            Builtins.mergestring(Ops.get_list(pi, ["info", "aliases"], []), ",")
          ) :
          ""
      )

      UI.ChangeWidget(Id("product_details"), :Value, rt_description)

      nil
    end

    # Logs wrong product with 'log_this' error and returns 'return_this'.
    # Added because of bnc #459461
    def LogWrongProduct(one_product, log_this, return_this)
      one_product = deep_copy(one_product)
      Builtins.y2error("Erroneous product: %1: %2", log_this, one_product)

      return_this
    end

    # Modifies repository info (adds some missing pieces).
    def AdjustRepositoryInfo(info)
      Builtins.foreach(
        Convert.convert(
          Ops.get(info.value, "IDs", []),
          :from => "list",
          :to   => "list <integer>"
        )
      ) do |one_repo|
        if one_repo == nil || one_repo == -1
          Builtins.y2warning("Wrong repo ID: %1", one_repo)
          next
        end
        source_data = Pkg.SourceGeneralData(one_repo)
        if source_data != nil && Builtins.haskey(source_data, "base_urls")
          Ops.set(
            info.value,
            "URLs",
            Ops.get_list(source_data, "base_urls", [])
          )
        else
          Builtins.y2error("No URLs for repo ID %1", one_repo)
        end
        if source_data != nil && Builtins.haskey(source_data, "alias")
          Ops.set(
            info.value,
            "aliases",
            [Ops.get_string(source_data, "alias", "")]
          )
        end
      end

      nil
    end

    #
    # **Structure:**
    #
    #     $[
    #          "IDs"  : [8, 9, 12],
    #          "URLs" : ["dvd://", "http://some/URL/", "ftp://another/URL/"],
    #          "aliases" : ["alias1", "alias2", "alias3"],
    #      ]
    def GetRepoInfo(this_product, all_products)
      ret = { "IDs" => [], "URLs" => [], "aliases" => [] }

      product_arch = Ops.get_string(this_product.value, "arch", "")
      product_name = Ops.get_string(this_product.value, "name", "")
      product_version = Ops.get_string(this_product.value, "version", "")

      Builtins.foreach(all_products.value) do |one_product|
        # if (one_product["status"]:`unknown != `available)	return;
        next if Ops.get_string(one_product, "arch", "") != product_arch
        next if Ops.get_string(one_product, "name", "") != product_name
        next if Ops.get_string(one_product, "version", "") != product_version
        if Builtins.haskey(one_product, "source") &&
            Ops.get_integer(one_product, "source", -1) != -1
          Ops.set(
            ret,
            "IDs",
            Builtins.add(
              Ops.get(ret, "IDs", []),
              Ops.get_integer(one_product, "source", -1)
            )
          )
        end
      end

      ret_ref = arg_ref(ret)
      AdjustRepositoryInfo(ret_ref)
      ret = ret_ref.value

      deep_copy(ret)
    end

    def GetAllProductsInfo
      all_products = Pkg.ResolvableProperties("", :product, "")

      all_products = Builtins.maplist(all_products) do |one_product|
        # otherwise it fills the log too much
        Builtins.foreach(["license", "description"]) do |key|
          if Builtins.haskey(one_product, key)
            Ops.set(
              one_product,
              key,
              Ops.add(
                Builtins.substring(Ops.get_string(one_product, key, ""), 0, 40),
                "..."
              )
            )
          end
        end
        deep_copy(one_product)
      end

      deep_copy(all_products)
    end

    def GetInstalledProducts
      installed_products = Builtins.filter(GetAllProductsInfo()) do |one_product|
        # Do not list the base product
        next false if Ops.get_string(one_product, "category", "addon") == "base"
        # BNC #475591: Only those `installed or `selected ones should be actually visible
        Ops.get_symbol(one_product, "status", :unknown) == :installed ||
          Ops.get_symbol(one_product, "status", :unknown) == :selected
      end

      deep_copy(installed_products)
    end

    def GetProductInfos
      all_products = GetAllProductsInfo()
      installed_products = GetInstalledProducts()

      repository_info = nil
      counter = -1

      @product_infos = {}

      Builtins.foreach(installed_products) do |one_product|
        # only add-on products should be listed
        if Builtins.haskey(one_product, "type") &&
            Ops.get_string(one_product, "type", "addon") != "addon"
          Builtins.y2milestone(
            "Skipping product: %1",
            Ops.get_string(
              one_product,
              "display_name",
              Ops.get_string(one_product, "name", "")
            )
          )
          next
        end
        counter = Ops.add(counter, 1)
        Builtins.y2milestone(
          "Product: %1, Info: %2",
          one_product,
          repository_info
        )
        if repository_info == nil
          Builtins.y2warning(
            "No matching repository found for product listed above"
          )
        end
        repository_info = (
          one_product_ref = arg_ref(one_product);
          all_products_ref = arg_ref(all_products);
          _GetRepoInfo_result = GetRepoInfo(one_product_ref, all_products_ref);
          one_product = one_product_ref.value;
          all_products = all_products_ref.value;
          _GetRepoInfo_result
        )
        Ops.set(
          @product_infos,
          Builtins.tostring(counter),
          { "product" => one_product, "info" => repository_info }
        )
      end

      deep_copy(@product_infos)
    end

    # List of all selected repositories
    #
    #
    # **Structure:**
    #
    #     add_on_products = [
    #        $[
    #          "media" : 4, // ID of the source
    #          "product_dir" : "/",
    #          "product" : "openSUSE version XX.Y",
    #          "autoyast_product" : "'PRODUCT' tag for AutoYaST Export",
    #          "media_url" : "Zypp URL of the product",
    #        ],
    #        ...
    #      ]
    def ReadFromSystem
      AddOnProduct.add_on_products = []

      product_infos = Convert.convert(
        GetProductInfos(),
        :from => "map",
        :to   => "map <string, map>"
      )
      if product_infos == nil || product_infos == {}
        Builtins.y2warning("No add-on products have been found")
        return true
      end

      src_id = nil

      Builtins.foreach(product_infos) do |index, product_desc|
        src_id = Ops.get_integer(product_desc, ["info", "IDs", 0], -1)
        if src_id == nil || src_id == -1
          Builtins.y2error("Cannot get source ID from %1", product_desc)
          next
        end
        repo_data = Pkg.SourceGeneralData(src_id)
        AddOnProduct.add_on_products = Builtins.add(
          AddOnProduct.add_on_products,
          {
            "media"            => src_id,
            "product_dir"      => Ops.get_string(repo_data, "product_dir", "/"),
            "product"          => Ops.get_locale(
              repo_data,
              "name",
              Ops.get_locale(
                repo_data,
                "alias",
                _("No product found in the repository.")
              )
            ),
            "autoyast_product" => Ops.get_locale(
              product_desc,
              ["product", "name"],
              Ops.get_locale(
                repo_data,
                "name",
                Ops.get_locale(
                  repo_data,
                  "alias",
                  _("No product found in the repository.")
                )
              )
            ),
            "media_url"        => Pkg.SourceURL(src_id)
          }
        )
      end

      Builtins.y2milestone("Add-Ons read: %1", AddOnProduct.add_on_products)

      true
    end

    def RedrawAddOnsOverviewTable
      products = []

      product_infos = Convert.convert(
        GetProductInfos(),
        :from => "map",
        :to   => "map <string, map>"
      )

      product_infos = {} if product_infos == nil

      Builtins.y2milestone("Currently used add-ons: %1", product_infos)

      Builtins.foreach(product_infos) do |index, product_desc|
        products = Builtins.add(
          products,
          Item(
            Id(Builtins.sformat("product_%1", index)),
            Ops.get_locale(
              product_desc,
              ["product", "display_name"],
              Ops.get_locale(
                product_desc,
                ["product", "name"],
                _("Unknown product")
              )
            ),
            Ops.get_locale(product_desc, ["info", "URLs", 0], _("Unknown URL"))
          )
        )
      end

      UI.ChangeWidget(Id("list_of_addons"), :Items, products)
      AdjustInfoWidget()

      # Nothing to do delete when there are no product listed
      UI.ChangeWidget(
        Id(:delete),
        :Enabled,
        Ops.greater_than(Builtins.size(products), 0)
      )

      nil
    end

    def RunPackageSelector
      solve_ret = Pkg.PkgSolve(false)
      Builtins.y2milestone("Calling Solve() returned: %1", solve_ret)

      result = PackagesUI.RunPackageSelector({ "mode" => :summaryMode })

      return false if result != :accept

      Wizard.OpenNextBackDialog

      Builtins.y2milestone("Calling inst_rpmcopy")
      WFM.call("inst_rpmcopy")
      Builtins.y2milestone("Done")

      Wizard.CloseDialog

      true
    end

    # Removes the currently selected Add-On
    #
    # @return [Boolean] whether something has changed its state
    def RemoveProductWithDependencies
      pi = ReturnCurrentlySelectedProductInfo()
      if pi == nil || pi == {}
        Builtins.y2error("Cannot remove unknown product")
        return nil
      end

      product_name = Ops.get_locale(
        pi,
        ["product", "display_name"],
        Ops.get_locale(pi, ["product", "name"], _("Unknown product"))
      )

      if !Popup.AnyQuestion(
          Label.WarningMsg,
          Builtins.sformat(
            _(
              "Deleting the add-on product %1 may result in removing all the packages\n" +
                "installed from this add-on.\n" +
                "\n" +
                "Are sure you want to delete it?"
            ),
            product_name
          ),
          Label.DeleteButton,
          Label.CancelButton,
          :focus_no
        )
        Builtins.y2milestone("Deleting '%1' canceled", product_name)
        return nil
      end

      # TRANSLATORS: busy popup message
      UI.OpenDialog(Label(_("Removing product dependencies...")))
      # OpenDialog-BusyMessage

      src_ids = Ops.get_list(pi, ["info", "IDs"], [])

      # Temporary definitions
      pack_ret = false
      package_string = ""

      # ["pkg1 version release arch", "pkg2 version release arch", ... ]
      installed_packages = Builtins.maplist(Pkg.GetPackages(:installed, false)) do |inst_package|
        Builtins.regexpsub(
          inst_package,
          "(.*) (.*) (.*) (.*)",
          "\\1 \\2-\\3 \\4"
        )
      end

      # y2milestone ("Installed packages: %1", installed_packages);

      # All packages from Add-On / Repository
      packages_from_repo = Pkg.ResolvableProperties("", :package, "")

      packages_from_repo = Builtins.filter(packages_from_repo) do |one_package|
        # Package is not at the repositories to be deleted
        if !Builtins.contains(
            src_ids,
            Ops.get_integer(one_package, "source", -1)
          )
          next false
        end
        # Package *is* at the repository to delete

        # "name version-release arch", "version" already contains a release
        package_string = Builtins.sformat(
          "%1 %2 %3",
          Ops.get_string(one_package, "name", ""),
          Ops.get_string(one_package, "version", ""),
          Ops.get_string(one_package, "arch", "")
        )
        # The very same package (which is avaliable at the source) is also installed
        Builtins.contains(installed_packages, package_string)
      end

      Builtins.y2milestone(
        "%1 packages installed from repository",
        Builtins.size(packages_from_repo)
      )

      # Removing selected product, whatever it means
      # It might remove several products when they use the same name
      if (Ops.get_symbol(pi, ["product", "status"], :unknown) == :installed ||
          Ops.get_symbol(pi, ["product", "status"], :unknown) == :selected) &&
          Ops.get_string(pi, ["product", "name"], "") != ""
        Builtins.y2milestone(
          "Removing product: '%1'",
          Ops.get_string(pi, ["product", "name"], "")
        )
        Pkg.ResolvableRemove(
          Ops.get_string(pi, ["product", "name"], ""),
          :product
        )
      else
        Builtins.y2milestone("Product is neither `installed nor `selected")
      end

      # Removing repositories of the selected product
      Builtins.y2milestone(
        "Removing repositories: %1, url(s): %2",
        src_ids,
        Ops.get_list(pi, ["info", "URLs"], [])
      )
      Builtins.foreach(src_ids) do |src_id|
        if Ops.greater_than(src_id, -1)
          Builtins.y2milestone("Removing repository ID: %1", src_id)
          Pkg.SourceDelete(src_id)
        else
          Builtins.y2milestone("Product doesn't have any repository in use")
        end
      end

      # The product repository is already removed, checking all installed packages

      # All available packages
      available_packages = Builtins.maplist(Pkg.GetPackages(:available, false)) do |inst_package|
        Builtins.regexpsub(
          inst_package,
          "(.*) (.*) (.*) (.*)",
          "\\1 \\2-\\3 \\4"
        )
      end

      available_package_names = Pkg.GetPackages(:available, true)
      Builtins.y2milestone(
        "%1 available packages",
        Builtins.size(available_package_names)
      )

      status_changed = false

      # check all packages installed from the just removed repository
      Builtins.foreach(packages_from_repo) do |one_package|
        # "name version-release arch", "version" already contains a release
        package_string = Builtins.sformat(
          "%1 %2 %3",
          Ops.get_string(one_package, "name", ""),
          Ops.get_string(one_package, "version", ""),
          Ops.get_string(one_package, "arch", "")
        )
        # installed package is not available anymore
        if !Builtins.contains(available_packages, package_string)
          status_changed = true

          # it must be removed
          Builtins.y2milestone("Removing: %1", package_string)
          Pkg.ResolvableRemove(
            Ops.get_string(one_package, "name", "~~~"),
            :package
          )

          # but if another version is present, select if for installation
          if Builtins.contains(
              available_package_names,
              Ops.get_string(one_package, "name", "~~~")
            )
            Builtins.y2milestone(
              "Installing another version of %1",
              Ops.get_string(one_package, "name", "")
            )
            Pkg.ResolvableInstall(
              Ops.get_string(one_package, "name", ""),
              :package
            )
          end
        end
      end

      # See OpenDialog-BusyMessage
      UI.CloseDialog

      return RunPackageSelector() if status_changed

      true
    end

    def RunAddProductWorkflow
      WFM.CallFunction("inst_addon_update_sources", [])
      AddOnProduct.DoInstall
      # Write only when there are some changes
      Write()

      Pkg.SourceReleaseAll

      nil
    end

    # Cleanup UI - Prepare it for progress callbacks
    def SetWizardWindowInProgress
      Wizard.SetContents(
        _("Add-On Products"),
        Label(_("Initializing...")),
        _("<p>Initializing add-on products...</p>"),
        false,
        false
      )

      Wizard.SetTitleIcon("yast-addon")

      nil
    end

    # BNC #476417: When user cancels removing an add-on, we have to neutralize all
    # libzypp resolvables to their inital states
    def NeutralizeAllResolvables
      Builtins.foreach([:product, :patch, :package, :srcpackage, :pattern]) do |one_type|
        Builtins.y2milestone("Neutralizing all: %1", one_type)
        Pkg.ResolvableNeutral("", one_type, true)
      end

      nil
    end

    # Either there are no repositories now or they
    # were changed, neutralized, etc.
    def LoadLibzyppNow
      Builtins.y2milestone("Reloading libzypp")
      SetWizardWindowInProgress()

      # Reinitialize
      Pkg.TargetInitialize(Installation.destdir)
      Pkg.TargetLoad
      Pkg.SourceStartManager(true)

      nil
    end

    def RunAddOnsOverviewDialog
      Builtins.y2milestone("Overview Dialog")
      ret = :next

      # to see which products are installed
      Pkg.PkgSolve(true)

      CreateAddOnsOverviewDialog()
      RedrawAddOnsOverviewTable()

      userret = nil

      while true
        userret = UI.UserInput

        # Abort
        if userret == :abort || userret == :cancel
          Builtins.y2warning("Aborting...")
          ret = :abort
          break

          # Closing
        elsif userret == :next || userret == :finish
          Builtins.y2milestone("Finishing...")
          ret = :next
          break

          # Addin new product
        elsif userret == :add
          Builtins.y2milestone("Using new Add-On...")

          RunAddProductWorkflow() if RunWizard() == :next

          # Something has disabled all the repositories or finished
          # libzypp, reload it
          current_repos = Pkg.SourceGetCurrent(true)
          if current_repos == nil || Builtins.size(current_repos) == 0
            LoadLibzyppNow()
          end

          CreateAddOnsOverviewDialog()
          RedrawAddOnsOverviewTable()

          # Removing product
        elsif userret == :delete
          Builtins.y2milestone("Removing selected product...")

          rpwd = RemoveProductWithDependencies()
          Builtins.y2milestone("RPWD result was: %1", rpwd)

          # nil == user decided not to remove the product
          if rpwd == nil
            Builtins.y2milestone(
              "User decided not to remove the selected product"
            )
            next

            # false == user decided not confirm the add-on removal
            # libzypp has been already changed
            # BNC #476417: Getting libzypp to the previous state
          elsif rpwd == false
            Builtins.y2milestone("User aborted the package manager")

            SetWizardWindowInProgress()

            # Neutralizing all resolvables (some are usually marked for removal)
            NeutralizeAllResolvables()
            Pkg.SourceFinishAll

            LoadLibzyppNow()

            # true == packages and sources have been removed
          else
            # Store sources state
            Pkg.SourceSaveAll
          end

          CreateAddOnsOverviewDialog()
          RedrawAddOnsOverviewTable()

          # Redrawing info widget
        elsif userret == "list_of_addons"
          AdjustInfoWidget()

          # Calling packager directly
        elsif userret == :packager
          Builtins.y2milestone("Calling packager...")
          RunPackageSelector()

          CreateAddOnsOverviewDialog()
          RedrawAddOnsOverviewTable()

          # Everything else
        else
          Builtins.y2error("Uknown ret: %1", userret)
        end
      end

      Wizard.RestoreBackButton

      ret
    end
  end
end
