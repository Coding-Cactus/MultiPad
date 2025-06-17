FROM ruby:3.3

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

ENV APP_ENV=production
EXPOSE 4567

CMD ["bundle", "exec", "ruby", "./main.rb", "-o", "0.0.0.0"]
