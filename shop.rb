require 'sinatra'
require 'sinatra/reloader'
require 'openai'
require 'erb'
require 'json'
require 'benchmark'

$openAI = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])

# Prompt:
# Create a JSON schema for the data of an ecommerce store. The data consists of a list of Products and a Cart which
# contains Line items. A product has an id, a name, a price and a description. A line item has a reference to a
# product and a product count. The cart has a list of line items. Use UUIDs for all ids.
$jsonSchema = File.read 'schema.json'
$parsedJsonSchema = JSON.parse $jsonSchema

# Prompt:
# Create an HTML file that contains a modern bootstrap template for an ecommerce shop. The shop name is "MyShop"
# and should be displayed in a top navigation bar. Also include a right sidebar, that can be filled with additional
# content. Use comments to specify the locations at which additional (sidebar) content should be inserted.
# The navigation should contain a link "Admin" to the list of all products "/admin/products".
# Clicking on "MyShop" should open the root page "/".
$page_template = File.read 'templates/page.html'

FileUtils.cp 'templates/db.json', 'cache/db.json' unless File.exist? 'cache/db.json'
$state = JSON.parse File.read('cache/db.json')

def log_with_color(message, color_code)
  puts "\e[#{color_code}m#{message}\e[0m"
end

def ask_openai prompt
  response = $openAI.chat parameters: {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: prompt }],
    temperature: 0.7
  }
  response.dig("choices", 0, "message", "content")
end

def ask_openai_json prompt
  response = $openAI.chat parameters: {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: prompt }],
    temperature: 0.7,
    response_format: {
      type: 'json_schema',
      json_schema: {
        name: 'shop',
        schema: $parsedJsonSchema
      }
    }
  }
  response.dig("choices", 0, "message", "content")
end

def prompt_command question
  prompt = <<~PROMPT
    You are an ecommerce shopping system.
    Read your initial state from this JSON data file:
    #{JSON.generate $state}
    Use this JSON schema for these data:
    #{$jsonSchema}
    I will give you an instruction and you give me the new contents of the JSON file without any further descriptions.
    Instruction: "#{question}"
  PROMPT
  log_with_color "prompt_command()", 32
  log_with_color prompt.gsub(/\n/, ' ')[0, 137] + '...', 33
  response = nil
  time = Benchmark.measure { response = ask_openai_json prompt }
  log_with_color "Execution time: #{time.real.round(2)} seconds", 34
  $state = JSON.parse response
  File.write 'cache/db.json', response
end

def prompt_view_template question
  prompt = <<~PROMPT
    You are the generator for Mustache web page templates of an ecommerce shopping system.
    Use this JSON schema for the data that should be displayed with these templates:
    #{$jsonSchema}
    You are given these additional parameters:
    #{params.inspect}
    When generating Mustache HTML templates you use a bootstrap design.
    You add left an right margin around the page body.
    You use this HTML page layout template and embed the page HTML into it:
    #{$page_template}
    You put a page navigation header at the top of the page. The page title is "MyShop".
    All tables should be bordered and have striped, hoverable rows.
    All icons should be FontAwesome icons.
    When generating HTML forms, you use the information in the JSON schema.
    Create an Mustache HTML template output following the following specifications and only output the content of 
    the generated HTML template file without any further explanations:
    #{question}
  PROMPT
  log_with_color "prompt_view_template()", 32
  log_with_color prompt.gsub(/\n/, ' ')[0, 137] + '...', 33
  response = nil
  time = Benchmark.measure { response = (ask_openai prompt).gsub(/^```.+/, '').gsub(/```$/, '') }
  log_with_color "Execution time: #{time.real.round(2)} seconds", 34
  response
end

def prompt_view name, question, params
  return if name == 'page'
  template_file = "cache/#{name}.html"
  template = if File.exist? template_file
    File.read template_file
  else
    prompt_view_template(question).tap { File.write template_file, _1 }
  end
  prompt = <<~PROMPT
    You are the generator for web pages of an ecommerce shopping system.
    Read your initial state from this JSON data file:
    #{JSON.generate $state}
    Use this JSON schema for these data:
    #{$jsonSchema}
    You are given these additional parameters:
    #{params.inspect}
    You use the JSON data to fill these HTML Mustache template to render the HTML page,
    replacing all Mustache elements with the JSON data:
    #{template}
    Calculate all Mustache formulas yourself. 
    When generating HTML content you use a bootstrap design.
    All tables should be bordered and have striped, hoverable rows.
    All icons should be FontAwesome icons.
    When generating HTML forms, you use the information in the JSON schema.
    Reuse all of the HTML from the HTML template. 
    Create an HTML output following the following specifications and only output the content of 
    the generated HTML file without any further explanations:
    #{question}
  PROMPT
  log_with_color "prompt_view()", 32
  log_with_color prompt.gsub(/\n/, ' ')[0, 137] + '...', 33
  response = nil
  time = Benchmark.measure { response = (ask_openai prompt).gsub(/^```.+/, '').gsub(/```$/, '') }
  log_with_color "Execution time: #{time.real.round(2)} seconds", 34
  response
end

get '/' do
  prompt_view('products', <<~PROMPT, params)
    Display all products in grid of cards with two columns.
    For each product display the name and the price.
    A click on the product should open the URL '/products/:id' where :id is the id of the product.
    Also display the cart at the top of the right sidebar.    
    The cart should display all line item product names and the product counts, in one line for each item.
    The cart should also display the total cost of all product prices times the product counts.
    Use dollars as the currency.
    Also in the cart display a button to show the cart. The button URL is '/cart'.
    Draw a border around the cart.
  PROMPT
end

get '/products/:id' do
  prompt_view('product', <<~PROMPT, params)
    Display the single product with the id #{params['id']} in its full glory.
    Display all properties of the product.
    Display a button for adding the product to the cart. This buttons URL is '/cart/add/:id', 
    where :id is the product id.
    Also display a button for going back to the product list. This buttons URL is '/'
    Also display the cart at the top of the right sidebar.    
    The cart should display all line item product names and the product counts, in one line for each item.
    The cart should also display the total cost of all product prices times the product counts.
    Use dollars as the currency.
    Also in the cart display a button to show the cart. The button URL is '/cart'
    Draw a border around the cart.
  PROMPT
end

get '/cart' do
  prompt_view('cart', <<~PROMPT, params)
    Display the cart.
    For each line item display a row containing the product name, the product single price the product count,
    the total cost and a button to remove the line item from the cart. 
    The remove button URL is '/cart/remove/:id', where :id is the product id. 
    Below the line items, display the total cost of all products. 
    Use dollars as the currency.
    Display a button for checking out the cart. The URL of the button is '/cart/checkout'.
    Also display a button for going back to the product list. This buttons URL is '/'
  PROMPT
end

get '/cart/add/:id' do
  prompt_command <<~PROMPT
    Add the product with the id #{params['id']} to the cart.
    If the product wasn't already in the cart, set it's product count to one.
    If the product was already in the cart, increase it's product count by one.
  PROMPT
  redirect '/'
end

get '/cart/remove/:id' do
  prompt_command <<~PROMPT
    Remove the product with the id #{params['id']} from the cart.
    If the product isn't in the cart, do nothing.
    If the product is in the cart, completely remove it from the cart.
  PROMPT
  redirect '/cart'
end

get '/admin/products' do
  prompt_view('admin_products', <<~PROMPT, params)
    Display all products in a table one row for each product.
    Display the id, name and price for each product.
    Each product has a delete link with an icon.
    The URL for the delete link is '/admin/product/:id/delete'. Use the id of the respective product for ':id'.
    Each product has an edit link with an icon.
    The URL for the edit link is '/admin/products/:id/edit'. Use the ID of the respective product for ':id'.
    Display a button for creating a new product. The URL of the button is '/admin/products/new'.
  PROMPT
end

get '/admin/products/new' do
  prompt_view('admin_products_new', <<~PROMPT, params)
    Display a form for entering a new product.
    Include all product attributes except for the ID.
    The action URL of the form is '/admin/products'.
    Also add a back button to the form, that links to the URL '/admin/products'.
  PROMPT
end

post '/admin/products' do
  prompt_command "Create a new product with these properties: '#{params.inspect}'"
  redirect '/admin/products'
end

get '/admin/products/:id/edit' do
  prompt_view('admin_products_edit', <<~PROMPT, params)
    Display a form for editing the product with id #{params['id']}.
    Show all product attributes except for the ID.
    The current product data is in the parameters.
    The target URL of the form is '/admin/products/:id'. Use the ID of the respective product for ':id'.
    The HTTP method of the form is POST.
    Add a hidden field to the form with the name '_method' and the value 'PUT'.
    Also add a back button to the form, that links to the URL '/admin/products'.
  PROMPT
end

put '/admin/products/:id' do
  pp prompt_command "Update the product with the id #{params[:id]} using these properties: #{params.inspect}"
  redirect '/admin/products'
end

get '/admin/products/:id/delete' do
  prompt_command "Delete the product with the id #{params[:id]}"
  redirect '/admin/products'
end
