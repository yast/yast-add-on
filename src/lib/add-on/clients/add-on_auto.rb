require "yast"
require "installation/auto_client"

Yast.import "AutoInstall"
Yast.import "AddOnProduct"
Yast.import "Progress"

module Yast
  class AddOnAutoClient < ::Installation::AutoClient
    def run
      textdomain "add-on"

      Yast.include self, "add-on/add-on-workflow.rb"

      progress_orig = Yast::Progress.set(false)
      ret = super
      Yast::Progress.set(progress_orig)

      ret
    end

    def import(data)
      add_on_products = data.fetch("add_on_products", [])

      valid_add_on_products = add_on_products.reject.with_index(1) do |add_on, index|
        next false unless add_on.fetch("media_url", "").empty?

        log.error "Missing <media_url> value in the #{index}. add-on-product definition"

        # abort import/installation
        return false unless skip_add_on_and_continue?(index)

        true
      end

      AddOnProduct.Import("add_on_products" => valid_add_on_products)
    end

    # Returns an unordered HTML list summarizing the Add-on products
    #
    # Each item will contain information about
    #
    #   * URL, the "media_url" property
    #   * Path, the "product_dir" property which will be omitted wether is not present or is the default
    #           path ("/")
    #   * Product, the "product" property, unless it is not present
    #
    # @example
    #   <ul>
    #     <li>URL: dvd:///</li>
    #     <li>URL: http://product.url, Product: Product name</li>
    #   </ul>
    #
    # @return [String] an unordered HTML list
    def summary
      formatted_add_ons = AddOnProduct.add_on_products.map do |add_on|
        product = add_on["product"]
        product_dir = add_on["product_dir"]

        add_on_summary = []
        # TRANSLATORS: %s is an add-on URL
        add_on_summary << _("URL: %s") % CGI.escapeHTML(add_on["media_url"])

        if [nil, "", "/"].none?(product_dir)
          # TRANSLATORS: %s is a product path
          add_on_summary << _("Path: %s") % CGI.escapeHTML(product_dir)
        end

        if !(product.nil? || product.empty?)
          # TRANSLATORS: %s is the product
          add_on_summary << _("Product: %s") % CGI.escapeHTML(product)
        end

        "<li>#{add_on_summary.join(", ")}</li>"
      end

      ["<ul>", formatted_add_ons, "</ul>"].join("\n")
    end

    def modified?
      AddOnProduct.modified
    end

    def modified
      AddOnProduct.modified = true
    end

    def reset
      AddOnProduct.add_on_products = []
    end

    def change
      Wizard.CreateDialog
      AutoinstSoftware.pmInit
      PackageCallbacks.InitPackageCallbacks

      ret = RunAddOnMainDialog(
        false,
        true,
        true,
        Label.BackButton,
        Label.OKButton,
        Label.CancelButton,
        false
      )

      Wizard.CloseDialog

      ret
    end

    def export
      AddOnProduct.Export
    end

    # Creates sources from add on products
    #
    # This method always will return `true`. However, there are two scenarios that could happen and it is
    # worth to take in mind:
    #
    #   * system will be halted immediately as soon a required license will be rejected
    #   * a source could be omitted if there is an error adding it and no retries are performed
    #
    # @see {create_source}
    #
    # @return [true]
    def write
      AddOnProduct.add_on_products.each do |add_on|
        product = add_on.fetch("product", "")
        media_url = media_url_for(add_on)
        action = create_source(add_on, product, media_url)

        case action
        when :report_error
          report_error_for(product, media_url)
        when :halt_system
          halt_system
        end
      end

      # reread agents, redraw wizard steps, etc.
      AddOnProduct.ReIntegrateFromScratch

      true
    end

    def read
      if !PackageLock.Check
        log.error("Cannot get package lock")

        return false
      end

      log.info("Reseting Pkg")

      Pkg.PkgApplReset
      Pkg.PkgReset
      Pkg.TargetInitialize(Installation.destdir)
      Pkg.TargetLoad
      Pkg.SourceStartManager(true)
      Pkg.PkgSolve(true)

      ReadFromSystem()
    end

  private

    # Create repo and install product (if given)
    #
    # @param [Hash] add_on
    # @param [String] product
    # @param [String] media_url
    #
    # @return [Symbol] a symbol that represent an action
    #   :report_error if source could not be created
    #   :halt_system if a required license was not accepted
    #   :continue if source was created successfully
    def create_source(add_on, product, media_url)
      url = expand_url_for(add_on, media_url)
      product_dir = add_on.fetch("product_dir", "/")
      retry_on_error = add_on.fetch("ask_on_error", false)

      # Set addon specific sig-handling
      AddOnProduct.SetSignatureCallbacks(product)

      loop do
        source_id = Pkg.SourceCreate(url, product_dir)

        log.info("New source ID: #{source_id}")

        if [nil, -1].include?(source_id)
          retry_on_error &&= retry_again?(product, media_url)

          return :report_error unless retry_on_error
        elsif !accepted_license?(add_on, source_id)
          # Lic
          Pkg.SourceDelete(source_id)

          return :halt_system
        else
          # bugzilla #260613
          AddOnProduct.Integrate(source_id)

          adjust_source_attributes(add_on, source_id)
          install_product(product)

          return :continue
        end
      end
    end

    # Returns absolute media url for given add on
    #
    # @param [Hash] add_on
    #
    # @return [String] absolute media url or empty string
    def media_url_for(add_on)
      media_url = add_on.fetch("media_url", "")

      if media_url.start_with?("relurl://")
        media_url = AddOnProduct.GetAbsoluteURL(AddOnProduct.getBaseProductURL, media_url)

        log.info("relurl changed to #{media_url}", media_url)
      end

      media_url
    end

    # Expand url for given add_on
    #
    # @param [Hash] add_on
    # @param [String] media_url
    #
    # @return [String] expanded url
    def expand_url_for(add_on, media_url)
      AddOnProduct.SetRepoUrlAlias(
        Pkg.ExpandedUrl(media_url),
        add_on.fetch("alias", ""),
        add_on.fetch("name", "")
      )
    end

    # Checks if should be retried to look for the source at given url
    #
    # @param [String] product
    # @param [String] media_url
    #
    # @return [Boolean]
    def retry_again?(product, media_url)
      prompt = format(_("Make the add-on \"%s\" available via \"%s\"."), product, media_url)

      Popup.ContinueCancel(prompt)
    end

    # Report an error about fail adding a product
    #
    # @param [String] product
    # @param [String] media_url
    def report_error_for(product, media_url)
      # TRANSLATORS: The placeholders are for the product name and the URL.
      # TRANSLATORS: a fallback string for undefined product name
      product_name = product || _("<not_defined_name>")
      error_msg = format(_("Failed to add product \"%s\" via\n%s"), product_name, media_url)

      Report.Error(error_msg)
    end

    # Tries to confirm license if needed
    #
    # @param [Hash] add_on
    # @param [Integer] source_id
    #
    # @return [Boolean] true if is not needed to confirm license or ir accepted; false otherwise
    def accepted_license?(add_on, source_id)
      return true unless add_on.fetch("confirm_license", false)

      AddOnProduct.AcceptedLicenseAndInfoFile(source_id)
    end

    # Adjusts source attributes for given id
    #
    # At the moment to create source/repo through `Pkg.SourceCreate` is not possible to set attributes
    # directly. In consequence, the creation must be completed making use of `Pkg.SourceEditSet`
    #
    # @see {https://github.com/yast/yast-pkg-bindings YaST Package Bindings}
    #
    # @param [Hash] add_on
    # @param [Integer|Nil] source_id
    def adjust_source_attributes(add_on, source_id)
      sources = Pkg.SourceEditGet
      index = sources.find_index { |source| source["SrcId"] == source_id }

      return if index.nil?

      repo = sources[index]
      repo["name"] = preferred_name_for(add_on, repo)
      repo["priority"] = add_on["priority"] if add_on.key?("priority")

      log.info("Preferred name: #{repo["name"]}")

      Pkg.SourceEditSet(sources)
    end

    # Returns preferred name for add-on/repo
    #
    # Following below precedence
    #
    #   * name in the add_on/control file, if given
    #   * name of repo that matches with given media and product path, if any
    #   * name of given repo
    #
    # @param [Hash] addon
    # @param [Array] repo
    #
    # @return [String] preferred name for add-on/repo
    def preferred_name_for(add_on, repo)
      add_on_name = add_on.fetch("name", nil)

      return add_on_name unless add_on_name.nil? || add_on_name.empty? # name in control file, bnc#433981

      media = add_on.fetch("media")
      product_dir = add_on.fetch("product_dir")
      expanded_url = Pkg.ExpandedUrl(media)
      repos_at_url = Pkg.RepositoryScan(expanded_url)

      # {Pkg.RepositoryScan} output: [["Product Name", "Path"], ...]
      found_repo = repos_at_url.find { |r| r[1] == product_dir }
      return found_repo[0] if found_repo

      repo["name"]
    end

    # Installs given product
    #
    # @param [String] product
    def install_product(product)
      if product.empty?
        log.warn("No product to install")
      else
        log.info("Installing product: #{product}")
        Pkg.ResolvableInstall(product, :product)
      end
    end

    def skip_add_on_and_continue?(index)
      error_message = [
        "Error in the AutoYaST <add_on> section.",
        "Missing mandatory <media_url> value at index %d in the <add_on_products> definition.",
        "Skip the invalid product definition and continue with the installation?"
      ]
      popup_prompt = format(_(error_message.join("\n")), index)

      Popup.ContinueCancel(popup_prompt)
    end

    def halt_system
      log.warn("License not accepted, delete the repository and halt the system")

      SCR.Execute(path(".target.bash"), "/sbin/halt -f -n -p")
    end
  end
end
