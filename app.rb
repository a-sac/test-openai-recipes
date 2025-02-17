require 'sinatra'
require 'openai'
require 'dotenv'
require 'json'

Dotenv.load

client     = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
show_input = false
meal_description = nil
ingredients = []
meal_nutrition = {}
feedback_submit = false

get '/' do
  erb :index, locals: { meal_description: meal_description, show_input: show_input, ingredients: ingredients, meal_nutrition: meal_nutrition, feedback_submit: feedback_submit }
end

post '/toggle_div' do
  show_input = !show_input

  erb :index, locals: { meal_description: meal_description, show_input: show_input, ingredients: ingredients, meal_nutrition: meal_nutrition, feedback_submit: feedback_submit }
end

post '/remove' do
  ingredients = []
  meal_nutrition = []
  meal_description = nil
  feedback_submit = false

  erb :index, locals: { meal_description: meal_description, show_input: show_input, ingredients: ingredients, meal_nutrition: meal_nutrition, feedback_submit: feedback_submit }
end

post '/like' do
  puts "| USER FEEDBACK BEGIN |"
  puts "Ingredients: #{ingredients}"
  puts "Nutritional info: #{meal_nutrition}"
  puts "Description: #{meal_description}"
  puts "Result: Approve"
  puts "| USER FEEDBACK END |"

  ingredients = []
  meal_nutrition = []
  meal_description = nil
  feedback_submit = true

  erb :index, locals: { meal_description: meal_description, show_input: show_input, ingredients: ingredients, meal_nutrition: meal_nutrition, feedback_submit: feedback_submit }
end

post '/dislike' do
  puts "| USER FEEDBACK BEGIN |"
  puts "Ingredients: #{ingredients}"
  puts "Nutritional info: #{meal_nutrition}"
  puts "Description: #{meal_description}"
  puts "Result: Disapprove"
  puts "| USER FEEDBACK END |"

  ingredients = []
  meal_nutrition = []
  meal_description = nil
  feedback_submit = true

  erb :index, locals: { meal_description: meal_description, show_input: show_input, ingredients: ingredients, meal_nutrition: meal_nutrition, feedback_submit: feedback_submit }
end

post '/ask' do
  meal_description = params[:meal_description]
  show_input = !show_input
  feedback_submit = false

  if meal_description.nil? || meal_description.strip.empty?
    @error = "Please enter a valid meal description."
    meal_description = nil
    return erb :index, locals: { meal_description: meal_description, show_input: show_input, ingredients: ingredients, meal_nutrition: meal_nutrition }
  end

  begin
    response = client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          {
            role: 'user',
            content: <<~PROMPT
              Given the following meal description, extract a list of ingredients and their nutritional values.
              It's ok if the nutritional values of those ingredients are estimated but not exact.

              Meal description: "#{meal_description}"

              **Requirements:**
              - Each ingredient must include:
                - Name
                - Quantity
                - Energy (kcal)
                - Fat (g)
                - Carbohydrates (g)
                - Protein (g)
              - The response must be in **valid JSON** format.
              - The total nutritional values (`meal_nutrition`) must match the sum of individual ingredient values.
              - The portions shall be adjusted to one person.
              - Avoid using vague terms like 'to taste,' 'as needed,' or similar. 
              - Use only grams for the quantity, don't give any other info, just grams.
              - The name of the food, should be the one used on the USDA DB or any other reliable source you have access to.
              - Please, don't return text, the response must be only json and respect the format presented below.

              **Response Format:**
              ```json
              {
                "ingredients": [
                  { "name": "Ingredient Name", "quantity": "150g", "energy": X, "fat": X, "carbohydrates": X, "protein": X },
                  ...
                ],
                "meal_nutrition": { "energy": X, "fat": X, "carbohydrates": X, "protein": X }
              }
              ```

              **Error Handling:**
              - If you can't perform the action or there is any other error, return a **valid JSON** error response with the error description:
              ```json
              { error: "Unable to determine ingredients and nutrition for the given meal description." }
              ```
              - Do not return partial or incomplete data.
            PROMPT
          }
        ]
      }
    )

    puts "Raw response: #{response}"
    info = response.dig('choices', 0, 'message', 'content')

    if info
      json_match = info.match(/```.*json\n(.*?)\n```/m)
      json_string = json_match ? json_match[1] : info.strip

      parsed_data = JSON.parse(json_string) rescue nil
      puts "JSON: #{parsed_data}"

      if parsed_data && parsed_data['ingredients'] && parsed_data['meal_nutrition']
        ingredients = parsed_data['ingredients'].map do |ingredient|
          ingredient.transform_keys(&:to_sym)
        end
        puts "Ingredients: #{ingredients}"

        meal_nutrition = parsed_data['meal_nutrition'].transform_keys(&:to_sym)
        puts "Nutritional Info: #{meal_nutrition}"
      else
        @error = "We were not able to process your request. Please try again."
        show_input = true
      end
    else
      @error = "No response received. Please try again."
      show_input = true
    end

    erb :index, locals: { meal_description: meal_description, show_input: show_input, ingredients: ingredients, meal_nutrition: meal_nutrition, feedback_submit: feedback_submit }
  rescue OpenAI::Error => e
    @error = "An error occurred while contacting OpenAI: #{e.message}"
    erb :index, locals: { meal_description: meal_description, show_input: show_input, ingredients: ingredients, meal_nutrition: meal_nutrition, feedback_submit: feedback_submit }
  end
end
