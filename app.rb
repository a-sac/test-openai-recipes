# app.rb
require 'sinatra'
require 'openai'
require 'dotenv'

# Load environment variables from .env file
Dotenv.load

# Set up the OpenAI client
client     = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
show_input = false
ingredients = []
macros      = []

# Route to the homepage
get '/' do
  erb :index, locals: { show_input: show_input, ingredients: ingredients, macros: macros }
end

post '/toggle_div' do
  show_input = !show_input

  puts show_input

  erb :index, locals: { show_input: show_input, ingredients: ingredients, macros: macros }
end

# app.rb
post '/ask' do
  recipe_name = params[:recipe_name]
  show_input  = !show_input

  if recipe_name.nil? || recipe_name.strip.empty?
    @error = "Please enter a valid recipe name."
    return erb :index, { show_input: show_input, ingredients: ingredients, macros: macros }
  end

  begin
    # Query OpenAI for the recipe ingredients
    response = client.chat(
      parameters: {
        model: "gpt-4",  # You can use another model if needed
        messages: [
          { 
            role: 'user', 
            content: <<~PROMPT
              Give me a list of ingredients for a #{recipe_name} recipe. 
              If this is not a recipe, don't provide anything.
              For each ingredient, include the name of the food and a precise quantity. 
              Avoid using vague terms like 'to taste,' 'as needed,' or similar. 
              Each ingredient must have a clear and measurable quantity.
              The quantity is just for one person.
              Use only grams for the quantity, don't give any other info, just grams.
              To separate the name of the food and the quantity, use a "-"
              The name of the food, should be the one used on the USDA DB.
              Up to 7 ingredients. Only provide foods who are strictly necessary for the recipe.
              Finally, provide the total number of energy in kcal, fat in g, Carbohydrate in g, and protein in g of this recipe.
              It shall follow this structure: Energy: X kcal\nFat: X grams\nCarbohydrates: X grams\nProtein: X grams
              To separate the name of the macros and the quantity, use a ":"
            PROMPT
          }
        ]
      }
    )
    
    puts response
    # Extracting the ingredients from the response
    info = response.dig('choices', 0, 'message', 'content')

    puts "Raw response: #{info}"

    # If OpenAI response is not empty, process the ingredients
    if info
      # Clean up and structure the ingredients into name/quantity pairs
      ingredients, macros = process_info(info)
    end

    # Pass the recipe_name into the view along with the ingredients
    erb :index, locals: { recipe_name: recipe_name, show_input: show_input, ingredients: ingredients, macros: macros }

  rescue OpenAI::Error => e
    @error = "An error occurred while contacting OpenAI: #{e.message}"
    erb :index, locals: { recipe_name: recipe_name, show_input: show_input, ingredients: ingredients, macros: macros }
  end
end

def process_info(info)
  meal_info = info.split("\n")
  macros = []

  puts "Ingredients: #{meal_info}"  # Debug: Check the split ingredients

  structured_ingredients = meal_info.map do |ingredient|
    # Clean up the ingredient string (trim leading/trailing spaces)
    ingredient = ingredient.strip

    # Remove any leading number and dot pattern (e.g., "1.", "2.", etc.)
    ingredient = ingredient.sub(/^\d+\.\s*/, '')

    # Split at the first colon, which separates the name and quantity
    parts = ingredient.split("-", 2)

    # Skip if parts don't have both name and quantity
    if parts.length < 2
      parts = ingredient.split(":", 2)
      
      next if parts.length < 2

      macro_name = parts[0].strip
      macro_quantity = parts[1].strip

      puts "Processed macro: #{macro_name} - #{macro_quantity}"

      macros << { quantity: macro_quantity, name: macro_name }

      next
    end
    
    name = parts[0].strip
    quantity = parts[1].strip

    puts "Processed ingredient: #{name} - #{quantity}"  # Debug processed ingredient

    # Filter out ingredients with imprecise quantities like "to taste"
    if quantity.downcase.include?("to taste") || quantity.downcase.include?("as needed")
      next
    end

    # Return a hash with both the name and quantity
    { quantity: quantity, name: name }
  end
  
  # Filter out nil entries (in case some entries were malformed or excluded)
  [structured_ingredients.compact, macros.compact]
end
