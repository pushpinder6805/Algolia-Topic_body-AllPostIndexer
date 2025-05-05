# frozen_string_literal: true

class DiscourseAlgolia::PostIndexer < DiscourseAlgolia::Indexer
  QUEUE_NAME   = "algolia-posts"
  INDEX_NAME   = "discourse-posts"
  SETTINGS     = {
    "advancedSyntax"         => true,
    "attributeForDistinct"   => "topic.id",
    "attributesToHighlight"  => %w[topic.title topic.tags topic_body content],
    "attributesToRetrieve"   => %w[
      post_number
      content
      topic_body
      url
      image_url
      topic.title
      topic.tags
      topic.slug
      topic.url
      topic.views
      user.username
      user.name
      user.avatar_template
      user.url
      category.name
      category.color
      category.slug
      category.url
    ],
    "attributesToSnippet"    => ["topic_body:30", "content:30"],
    "customRanking"          => %w[desc(topic.views) asc(post_number)],
    "distinct"               => 1,
    "ranking"                => %w[typo words filters proximity attribute custom],
    "removeWordsIfNoResults" => "allOptional",
    "searchableAttributes"   => ["topic.title,topic.tags,topic_body,content"],
  }

  def queue(ids)
    Post.includes(:user, topic: %i[tags category shared_draft])
        .where(id: ids)
  end

  # ------------------------------------------------------------------------------------------------
  # Only index posts whose topic exists (not nil) and isn't deleted
  # ------------------------------------------------------------------------------------------------
  def should_index?(post)
    return false if post.blank?
    return false if post.topic.nil?                # <— guard against nil topic
    return false if post.topic.deleted_at.present? # <— skip deleted topics

    true
  end

  def to_object(post)
    topic = post.topic

    # Safely pull the first post’s cooked HTML (or fallback to empty string)
    first_cooked = topic&.first_post&.cooked.to_s
    topic_body  = Nokogiri::HTML5.fragment(first_cooked).text

    object = {
      objectID:    post.id,
      url:         post.url,
      post_id:     post.id,
      post_number: post.post_number,
      created_at:  post.created_at.to_i,
      updated_at:  post.updated_at.to_i,
      reads:       post.reads,
      like_count:  post.like_count,
      image_url:   post.image_url,
      word_count:  post.word_count,
      content:     Nokogiri::HTML5.fragment(post.cooked).text,
      topic_body:  topic_body,

      user: {
        id:              post.user.id,
        url:             "/u/#{post.user.username_lower}",
        name:            post.user.name,
        username:        post.user.username,
        avatar_template: post.user.avatar_template,
      },

      topic: {
        id:         topic.id,
        url:        topic.url,
        title:      topic.title,
        views:      topic.views,
        slug:       topic.slug,
        like_count: topic.like_count,
        tags:       topic.tags.map(&:name),
      },
    }

    if cat = topic.category
      object[:category] = {
        id:    cat.id,
        url:   cat.url,
        name:  cat.name,
        color: cat.color,
        slug:  cat.slug,
      }
    end

    object
  end
end
