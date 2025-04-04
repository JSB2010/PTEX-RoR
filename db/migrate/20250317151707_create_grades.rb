class CreateGrades < ActiveRecord::Migration[8.0]
  def change
    create_table :grades do |t|
      t.string :course
      t.string :letter_grade
      t.decimal :numeric_grade
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
