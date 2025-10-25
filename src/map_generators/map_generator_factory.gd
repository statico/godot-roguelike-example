class_name MapGeneratorFactory
extends RefCounted

# Different types of maps. Quest maps and things like Sokoban would have enum values here.
enum GeneratorType { DUNGEON, ARENA }


static func create_generator(type: GeneratorType) -> BaseMapGenerator:
	match type:
		GeneratorType.DUNGEON:
			return DungeonGenerator.new()
		GeneratorType.ARENA:
			return ArenaGenerator.new()
		_:
			Log.e("Unknown generator type")
			return null
