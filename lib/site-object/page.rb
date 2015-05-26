# Page objects are containers for all of the functionality of a page that you want to expose for testing
# purposes. When you create a page object you define a URL to access it, elements for all of the page 
# elements that you want to work with as well as higher level methods that use those elements to perform
# page operations.
#
# Here's a very simple account edit page example that has two fields and one button and assumes
# that you've defined a site object called 'ExampleSite.'
#
#  class AccountDetailsEditPage < ExampleSite::Page 
#    set_url "/accounts/{account_code}/edit" # Parameterized URL.
#  
#    element(:first_name)   {|b| b.text_field(:id, 'fname') } # text_field is a Watir method.
#    element(:last_name)    {|b| b.text_field(:id, 'fname') } # text_field is a Watir method.
#    element(:save)         {|b| b.button(:id, 'fname') }     # text_field is a Watir method.
#
#    def update(fname, lname) # Very simple method that uses the page elements defined above.
#      first_name.set fname
#      last_name.set  lname
#      save.click
#    end
#  end
#
# The URL defined in the example above is "parameterized" ({account_code} is a placeholder.) 
# You don't need to specify parameters for a URL, but if you do you need to call the page with a hash
# argument. To use the page after initializing an instance of the site object:
#
#  site.account_details_edit_page(account_code: 12345) 
#
# Pages only take arguments if the URL is parameterized. 
#
# Note that in the example above that there's no explicit navigation call. This is because the site will 
#look at its current URL and automatically navigate to the page if it's not already on it.
#
# Here's a simple page object for the rubygems.org search page. Note that no page URL is 
# defined using the PageObject#set_url method. This is because the page URL for the landing page is
# the same as the base URL for the site. When a page URL isn't explicitly defined the base URL is used 
# in its place:
#
#  class LandingPage < RubyGems::Page
#    element(:search_field)  { |b| b.browser.text_field(:id, 'home_query') }
#    element(:search_submit) { |b| b.browser.input(:id, 'search_submit')   }
#  
#    def search(criteria)
#      search_field.set('rails')
#      search_submit.click
#      expect_page(SearchResultsPage)
#    end
#  end
#
# Page objects aren't initialized outside of the context of a site object. When a site object is initialized
# it creates accessor methods for each page object that inherits from the site's page class. In the 
# example above, the LandingPage class inherits from the RubyGems site object's page class so you'd 
# be able to use it once you've initialized a RubyGems site:
#
#  site.landing_page.search("rails") # Returns an instance of the landing page after performing a search.
#
# Because the site object has accessor methods for all of its pages and page navigation is automatic
# it's not always necessary to specify a page object directly. But you can get one if need one:
#
#  page = site.some_page
#  =><SomePage>
module PageObject

  module PageClassMethods
    attr_reader :arguments, :browser, :navigation_disabled, :page_elements, :page_features, :page_url, :site, :unique_methods, :url_template, :url_matcher

    # Looks up all of the descendants of the current class. Used to figure out which page object classes
    # belong to the site.
    def descendants
      ObjectSpace.each_object(Class).select { |klass| klass < self }
    end

    # This method can be used to disable page navigation when defining a page class (it sets an 
    # instance variable called @navigation during initialization.) The use case for this is a page
    # that can't be accessed directly and requires some level of browser interaction to reach. 
    # To disable navigation:
    #
    #  class SomePage < SomeSite::Page
    #    disable_automatic_navigation true
    #  end
    #
    # When navigation is disabled there will be no automatic navigation when the page is called.
    # If the current page is not the page that you want a SiteObject::WrongPageError will 
    # be raised.
    # If the visit method is called on the page a SiteObject::PageNavigationNotAllowedError 
    # will be raised. 
    def disable_automatic_navigation
      @navigation_disabled = true
    end

    # Used to define access to a single HTML element on a page. This method takes two arguments:
    # * A symbol representing the element you are defining. This symbol is used to create an accessor 
    #   method on the page object.
    # * A block where access to the HTML element gets defined.
    #
    # Example: The page you are working with has a "First Name" field:
    #
    #  element(:first_name) { |b| b.text_field(:id 'signup-first-name') }
    #
    # In the example above,  the block argument 'b' is the browser object that will get passed down from 
    # the site to the page and used when the page needs to access the element. You can actually use any 
    # label for the block argument but it's recommended that you use something like 'b' or 'browser'
    # consistently here because it's always going to be some sort of browser object.
    #
    # When page objects get initialized they'll create an accessor method for the element and you can
    # then work with the element in the same way you'd work with it in Watir or Selenium.
    #
    # The element method is aliased to 'el' and using this alias is recommended as it saves space:
    #
    #  el(:first_name) { |b| b.text_field(:id 'signup-first-name') }
    def element(name, &block)
      @page_elements ||= []
      @page_elements << name.to_sym     
      define_method(name) do
        block.call(@browser)
      end
    end
    alias :el :element

    # Returns an array of symbols representing the required arguments for the page's page URL.
    def required_arguments
      @arguments ||= @url_template.keys.map { |k| k.to_sym }
    end

    # Used to define the full or relative URL to the page. Typically, you will *almost* *always* want to use 
    # this method when defining a page object (but see notes below.) The URL can be defined in a number 
    # of different ways. Here are some examples using Google News:
    #
    # *Relative* *URL*
    #
    #  set_url "/nwshp?hl=en"
    #
    # Relative URLs are most commonly used when defining page objects. The idea here is that you can 
    # change the base_url when calling the site object, which allows you to use the same code across 
    # multiple test environments by changing the base_url as you initialize a site object.
    #
    # *Relative* *URL* *with* *URL* *Templating*
    #  set_url "/nwshp?hl={language}"
    #
    # This takes the relative URL example one step further, allowing you to set the page's parameters.
    # Note that the the language specified in the first relative URL example ('en') was replaced by 
    # '{language}' in this one. Siteobject uses the Addressable library, which supports this kind of 
    # templating. When you template a value in the URL, the page object will allow you to specify the 
    # templated value when it's being initialized. Here's an example of how this works using a news site. 
    # Here's the base site object class:
    #
    #  class NewsSite
    #    include SiteObject
    #  end
    #
    # Here's a page object for the news page, templating the language value in the URL:
    #
    #  class NewsPage < NewsSite::Page
    #    set_url "/news?l={language}"
    #  end
    #
    # After you've initialized the site object you can load the Spanish or French versions of the 
    # page by changing the hash argument used to call the page from the site object:
    #
    #  site = NewsSite.new(base_url: "http://news.somesite.com")
    #  site.news_page(language: 'es')
    #  site.news_page(language: 'fr')
    #
    # In addition to providing a hash of templated values when initializing a page you can also use 
    # an object, as long as that object responds to all of the templated arguments in the page's
    # URL definition. Here's a simple class that has a language method that we can use for the news
    # page described above:
    #
    #  class Country
    #    attr_reader :language
    #
    #    def initialize(lang)
    #      @language = lang
    #    end
    #  end
    #
    # In the example below, the Country class is used to create a new new country object called 'c'.
    # This object has been initialized with a Spanish language code and the news page 
    # will load the spanish version of the page when it's called with the country object. 
    #
    #  site = NewsSite.new(base_url: "http://news.somesite.com")
    #  c = Country.new('es')
    #  => <Country:0x007fcb0dc67f98 @language="es">
    #  c.language
    #  => 'es'
    #  site.news_page(c)
    #  => <NewsPage:0x003434546566>
    #
    # If one or more URL parameters are missing when the page is getting initialized then the page
    # will look at the hash arguments used to initialize the site. If the argument the page needs is
    # defined in the site's initialization arguments it will use that. For example, if the site 
    # object is initialized with a port, subdomain, or any other argument you can use those values
    # when defining a page URL. Example:
    #
    #  class ConfigPage < MySite::Page
    #    set_url "/foo/{subdomain}/config"
    #  end
    #
    #  site = MySite.new(subdomain: 'foo')
    #  => <MySite:0x005434546511>
    #  site.configuration_page # No need to provide a subdomain here as long as the site object has it.
    #  => <ConfigPage:0x705434546541> 
    #
    # *Full* *URL*
    #  set_url "http://news.google.com/nwshp?hl=en"
    #
    # Every once in a while you may not want to use a base URL that has been defined. This allows you
    # to do that. Just define a complete URL for that page object and that's what will get used; the
    # base_url will be ignored.
    #
    # *No* *URL* 
    #
    # The set_url method is not mandatory. when defining a page. If you don't use set_url in the page 
    # definition then the page will defined the base_url as the page's URL. 
    def set_url(url)
      url ? @page_url = url : nil
    end  

    def set_url_template(base_url)    
      begin
        case @page_url.to_s
        when '' # There's no page URL so just assume the base URL          
          @url_template = Addressable::Template.new(base_url)
        when /(http:\/\/|https:\/\/)/i
          @url_template = Addressable::Template.new(@page_url)
        else
          @url_template = Addressable::Template.new(Addressable::URI.parse("#{base_url}#{@page_url}"))
        end
      rescue Addressable::URI::InvalidURIError => e
        raise SiteObject::PageInitError, "Unable to initialize #{self.class} because there's no base_url defined for the site and the page object URL that was defined was a URL fragment (#{@page_url})\n\n#{caller.join("\n")}"    
      end
    end

    # Optional. Allows you to specify a fallback mechanism for checking to see if the correct page is
    # being displayed. This only gets used in cases where the primary mechanism for checking a page
    # (the URL template defined by Page#set_url) fails to match the current browser URL. When that 
    # happens the regular expression defined here will be applied and the navigation check will pass
    # if the regular expression matches the current browser URL. 
    #
    # In most cases, you won't need to define a URL matcher and should just rely on the default page
    # matching that uses the page's URL template. The default matching should work fine for most cases.
    def set_url_matcher(regexp)
      regexp ? @url_matcher = regexp : nil
    end

    # Used to import page features for use within the page. Example:
    #
    #  class ConfigPage < MySite::Page
    #    use_features :footer, :sidebar 
    #  end
    #
    # Then, once the page object has been initialized:
    #
    #  site.config_page.footer.about.click
    #
    # Use the PageFeature class to define page features.
    def use_features(*args)
      @page_features = args
    end
  end

  module PageInstanceMethods
    attr_reader :arguments, :browser, :navigation_disabled, :page_elements, :page_features, :page_url, :required_arguments, :site, :url_template, :url_matcher

    # Takes the name of a page class. If the current page is of that class then it returns a page
    # object for the page. Raises a SiteObject::WrongPageError if that's not the case.
    # It's generally not a good idea to put error checking inside a page object. This should only be 
    # used in cases where there is a page transition and that transition is always expected to work.
    def expect_page(page)
      @site.expect_page(page)
    end

    # There's no need to ever call this directly. Initializes a page object within the context of a 
    # site object. Takes a site object and a hash of configuration arguments. The site object will 
    # handle all of this for you. 
    def initialize(site, args={})
      @browser = site.browser  
      @navigation_disabled = self.class.navigation_disabled
      @page_url = self.class.page_url
      @page_elements = self.class.page_elements
      @page_features = self.class.page_features
      @required_arguments = self.class.required_arguments
      @site = site
      @url_matcher = self.class.url_matcher 
      @url_template = self.class.url_template    

      # Try to expand the URL template if the URL has parameters. 
      @arguments = {}.with_indifferent_access # Stores the param list that will expand the url_template after examining the arguments used to initialize the page.
      if @required_arguments.length > 0
        @required_arguments.each do |arg| # Try to extract each URL argument from the hash or object provided, OR from the site object.
          if args.is_a?(Hash) && !args.empty?
            if args.with_indifferent_access[arg] #The hash has the required argument.
              @arguments[arg]= args.with_indifferent_access[arg]
            elsif @site.respond_to?(arg)
              @arguments[arg]= site.send(arg)
            else
              raise SiteObject::PageInitError, "#{args.class} was provided, but this object did not respond to :#{arg}, which is necessary to build an URL for the #{self.class.name} page.\n\n#{caller.join("\n")}"
            end
          # elsif args.is_a?(Hash) && args.empty?
          #   raise SiteObject::PageInitError, "An attempt to initialize the #{self.class.name} page object failed because no page arguments were provided. This page object requires the following arguments for initialization: :#{@required_arguments.join(", :")}\n\n#{caller.join("\n")}."
          elsif args # Some non-hash object was provided.
            if args.respond_to?(arg) #The hash has the required argument.
              @arguments[arg]= args.send(arg)
            elsif @site.respond_to?(arg)
              @arguments[arg]= site.send(arg)
            else
              raise SiteObject::PageInitError, "#{args.class} was provided, but this object did not respond to :#{arg}, which is necessary to build an URL for the #{self.class.name} page.\n\n#{caller.join("\n")}"
            end
          else
            # Do nothing here.
          end
        end
      elsif @required_arguments.length >  0 && !args
        raise SiteObject::PageInitError, "No object was provided when attempting to initialize #{self.class.name}. This page object requires the following arguments for initialization: :#{@required_arguments.join(', :')}.\n\n#{caller.join("\n")}"
      elsif @required_arguments.length == 0 && !args
        unless @args.is_a?(Hash) && args.empty?
          raise SiteObject::PageInitError, "#{args.class} was provided as a #{self.class.name} initialization argument, but the page URL doesn't require any arguments.\n\n#{caller.join("\n")}"
        end
      else
        # Do nothing here.
      end
      @url = @url_template.expand(@arguments).to_s

      @page_features ||= []
      @page_features.each do |arg|
        self.class_eval do
          klass = eval("#{arg.to_s.camelize}")
          if klass.alias
            define_method(klass.alias) do
              klass.new(@browser, args)
            end
          else
            define_method(arg) do
              klass.new(@browser, args)
            end
          end
        end
      end
      
      @site.most_recent_page = self
      unless on_page?
        if @navigation_disabled
          if page = @site.page
            raise SiteObject::PageNavigationNotAllowedError, "The #{self.class.name} page could not be accessed. Navigation is intentionally disabled for this page and the browser was displaying the #{@site.page.class.name} page when you tried to access it.\n\nPAGE URL:\n------------\n#{@site.browser.url}\n\n#{caller.join("\n")}"
          else
            raise SiteObject::PageNavigationNotAllowedError, "The #{self.class.name} page could not be accessed. Navigation is intentionally disabled for this page and the page that the browser was displaying could not be recognized.\n\nPAGE URL:\n------------\n#{@site.browser.url}\n\nPAGE TEXT:\n------------\n#{@site.browser.text}\n\n#{caller.join("\n")}"
          end
        end         
        visit         
      end
    end

    # Custom inspect method so that console output doesn't get in the way when debugging.
    def inspect
      "#<#{self.class.name}:#{object_id} @url_template=#{@url_template.inspect}>"
    end
    
    # Returns true if the page defined by the page object is currently being displayed in the browser,
    # false if not. It does this in two different ways, which are described below.
    #
    # A page always has a URL defined for it. This is typically done by using the Page.set_url method
    # to specify a URL when defining the page. You can skip using the set_url method but in that case
    # the page URL defaults to the base URL defined for the site object. 
    #
    # The default approach for determining if the page is being displayed relies on the URL defined for
    # the page. This method first does a general match against the current browser URL page's URL template.
    # If a match occurs here, and there are no required arguments for the page the method returns true.
    # If the page's URL template does require arguments the method performs an additional check to 
    # verify that each of the arguments defined for the page match what's in the current browser URL. 
    # If all of the arguments match then the method will return true. 
    #
    # This should work for most cases but may not always be enough. For example, there may be a redirect
    # and the URL used to navigate to the page may not be the final page URL. There's a fallback 
    # mechanism for these sorts of situations. You can use the Page.set_url_matcher method to define a
    # regular expression that the method will use in place of the URL template. If the regular expression
    # matches, then the method will return true even if the URL wouldn't match the URL template. 
    #
    # It's better to use the default URL matching if possible. But if for some reason it's not feasible
    # you can use the alternate method to specify how to match the page.
    def on_page?
      url = @browser.url    
      
      if @url_matcher && @url_matcher =~ url
        return true
      elsif @url_template.match(url)
        if @arguments.empty?
          return true
        else
          if page_args = @url_template.extract(Addressable::URI.parse(url))
            page_args = page_args.with_indifferent_access
            return true if @arguments.all? { |k, v| page_args[k] == v.to_s }
          end
        end
      end
      false
    end

    # Refreshes the page. 
    def refresh # TODO: Isolate browser library-specific code so that the adding new browser
      if @browser.is_a?(Watir::Browser) 
        @browser.refresh
      elsif @browser.is_a?(Selenium::WebDriver::Driver)
        @browser.navigate.refresh
      else
        raise SiteObject::BrowserLibraryNotSupportedError, "Only Watir-Webdriver and Selenium Webdriver are currently supported. Class of browser object: #{@browser.class.name}"
      end
      self
    end

    # Navigates to the page that it's called on. Raises a SiteObject::PageNavigationNotAllowedError when 
    # navigation has been disabled for the page. Raises a SiteObject::WrongPageError if the 
    # specified page isn't getting displayed after navigation.
    def visit
      if @navigation_disabled
        raise SiteObject::PageNavigationNotAllowedError, "Navigation has been disabled for the #{self.class.name} page. This was done when defining the page class and usually means that the page can't be reached directly through a URL and requires some additional work to access."
      end       
      if @browser.is_a?(Watir::Browser)
        @browser.goto(@url)
      elsif @browser.is_a?(Selenium::WebDriver::Driver)
        @browser.get(@url)
      else
        raise SiteObject::BrowserLibraryNotSupportedError, "Only Watir-Webdriver and Selenium Webdriver are currently supported. Class of browser object: #{@browser.class.name}"
      end     
      
      if @url_matcher
        raise SiteObject::WrongPageError, "Navigation check failed after attempting to access the #{self.class.name} page. Current URL #{@browser.url} did not match #{@url_template.pattern}. A URL matcher was also defined for the page and the secondary check against the URL matcher also failed. URL matcher: #{@url_matcher}" unless on_page?
      else
        raise SiteObject::WrongPageError, "Navigation check failed after attempting to access the #{self.class.name} page. Current URL #{@browser.url} did not match #{@url_template.pattern}" unless on_page?
      end

      @site.most_recent_page = self 
      self
    end
  end
end