require "yast"
require "y2packager/resolvable"

# Yast namespace
module Yast
  # Describes all Add-Ons which are not Add-On-Products or Base-Products.
  # Usually custom or 3rd party repositories.

  class AddOnOthersClass < Module
    include Yast::Logger

    #     add_on_others = [
    #        {
    #          "media" => 4, # ID of the source
    #          "name" : "openSUSE version XX.Y",
    #          "media_url"=>"dvd:/?devices=/dev/sr1"
    #          ....
    #        },
    #        ...
    #      ]
    attr_reader :add_on_others

    def main
      Yast.import "Pkg"
      textdomain "add-on"

      @add_on_others = []
    end

    def Read
      # Removing all repos which have installed based products
      # and add-on products.
      installed_product_names = Y2Packager::Resolvable.find(kind: :product, status: :installed).map(&:name)
      installed_available_products = Y2Packager::Resolvable.find(kind: :product, status: :available).select do |p|
        installed_product_names.include?(p.name)
      end

      installed_src_ids = installed_available_products.map(&:source).uniq
      other_repo_ids = Pkg.SourceGetCurrent(true) - installed_src_ids
      @add_on_others = other_repo_ids.map { |id| Pkg.SourceGeneralData(id) }
    end

    # Returns all enabled user added repos which are not base products or add-on products.
    #
    # @return [Hash] User defined repos.
    #
    # @example This is an XML file created from exported map:
    #      <add-on>
    #        <add_on_others config:type="list">
    #          <listentry>
    #            <media_url>ftp://server.name/.../</media_url>
    #            <alias>alias name</alias>
    #            <priority config:type="integer">20</priority>
    #            <name>Repository name</name>
    #            <product_dir>/</product_dir>
    #          </listentry>
    #          ...
    #        </add_on_others>
    #      </add-on>
    def Export
      others = @add_on_others.map do |p|
        { "media_url"   => p["url"],
          "alias"       => p["alias"],
          "priority"    => p["priority"],
          "name"        => p["name"],
          "product_dir" => p["product_dir"] }
      end
      { "add_on_others" => others }
    end

    publish function: :Export, type: "map ()"
    publish function: :Read, type: "map()"
  end

  AddOnOthers = AddOnOthersClass.new
  AddOnOthers.main
end
