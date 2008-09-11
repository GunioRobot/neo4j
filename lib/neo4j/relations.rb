
require 'neo4j/transactional'

module Neo4j
  
  
  #
  # Enables finding relations for one node
  #
  class Relations
    include Enumerable
    
    attr_reader :internal_node 
    
    def initialize(internal_node)
      @internal_node = internal_node
      @direction = Direction::BOTH
    end
    
    def outgoing(type = nil)
      @type = type
      @direction = Direction::OUTGOING
      self
    end

    def incoming(type = nil)
      @type = type      
      @direction = Direction::INCOMING
      self
    end

    def  both(type = nil)
      @type = type      
      @direction = Direction::BOTH
      self
    end
    
    def empty?
      !iterator.hasNext
    end
    
    # 
    # Returns the relationship object to the other node.
    #
    def [](other_node)
      find {|r| r.end_node.neo_node_id == other_node.neo_node_id}
    end
    
    
    
    def each
      iter = iterator
      while (iter.hasNext) do
        n = iter.next
        yield RelationWrapper.new(n)
      end
    end

    
    def nodes
      RelationNode.new(self)
    end
    
    def iterator
      return @internal_node.getRelationships(@direction).iterator if @type.nil?
      return @internal_node.getRelationships(RelationshipType.instance(@type), @direction).iterator unless @type.nil?
    end
  end


  class RelationNode
    include Enumerable
    
    def initialize(relations)
      @relations = relations
    end
    
    def each
      @relations.each do |relation|
        yield relation.other_node(@relations.internal_node)
      end
    end
  end
  
  #
  # Wrapper class for a java org.neo4j.api.core.Relationship class
  #
  class RelationWrapper
    extend Neo4j::Transactional
    
    def initialize(r)
      @internal_r = r
    end
  
    def end_node
      id = @internal_r.getEndNode.getId
      Neo.instance.find_node id
    end
  
    def start_node
      id = @internal_r.getStartNode.getId
      Neo.instance.find_node id
    end
  
    def other_node(node)
      id = @internal_r.getOtherNode(node).getId     
      Neo.instance.find_node id
    end
    
    #
    # Deletes the relationship between two nodes.
    # Will fire a RelationshipDeletedEvent on the start_node class.
    #
    def delete
      from_node = start_node
      to_node = end_node
      @internal_r.delete
      clazz = from_node.class
      type = @internal_r.getType().name()
      clazz.fire_event(RelationshipDeletedEvent.new(from_node, to_node, type))
    end

    def set_property(key,value)
      @internal_r.setProperty(key,value)
    end    
    
    def property?(key)
      @internal_r.hasProperty(key)
    end
    
    def get_property(key)
      @internal_r.getProperty(key)
    end
    
    transactional :delete
  end

  #
  # Enables traversal of nodes of a specific type that one node has.
  #
  class NodesWithRelationType
    include Enumerable
    extend Neo4j::Transactional
    
    # TODO other_node_class not used ?
    def initialize(node, type, other_node_class = nil, &filter)
      @node = node
      @type = RelationshipType.instance(type)      
      @other_node_class = other_node_class
      @filter = filter
      @depth = 1
    end
    
       
    def each
      stop = DepthStopEvaluator.new(@depth)
      traverser = @node.internal_node.traverse(org.neo4j.api.core.Traverser::Order::BREADTH_FIRST, 
        stop, #StopEvaluator::DEPTH_ONE,
        ReturnableEvaluator::ALL_BUT_START_NODE,
        @type,
        Direction::OUTGOING)
      iter = traverser.iterator
      while (iter.hasNext) do
        node = Neo4j::Neo.instance.load_node(iter.next)
        if !@filter.nil?
          res =  node.instance_eval(&@filter)
          next unless res
        end
        yield node
      end
    end
      
    #
    # Creates a relationship between this and the other node.
    # Returns the relationship object that has property like a Node has.
    #
    #   n1 = Node.new # Node has declared having a friend type of relationship 
    #   n2 = Node.new
    #   
    #   relation = n1.friends.new(n2)
    #   relation.friend_since = 1992 # set a property on this relationship
    #
    def new(other)
      r = @node.internal_node.createRelationshipTo(other.internal_node, @type)
      RelationWrapper.new(r)
    end
    
    
    #
    # Creates a relationship between this and the other node.
    # Returns self so that we can add several nodes like this:
    # 
    #   n1 = Node.new # Node has declared having a friend type of relationship
    #   n2 = Node.new
    #   n3 = Node.new
    #   
    #   n1 << n2 << n3
    #
    # This is the same as:
    #  
    #   n1.friends.new(n2)
    #   n1.friends.new(n3)
    #
    def <<(other)
      # TODO, should we check if we should create a new transaction ?
      @node.internal_node.createRelationshipTo(other.internal_node, @type)
      @node.class.fire_event(RelationshipAddedEvent.new(@node, other, @type.name))
      self
    end
    
    transactional :<<
  end
  
  #
  # This is a private class holding the type of a relationship
  # 
  class RelationshipType
    include org.neo4j.api.core.RelationshipType

    @@names = {}
    
    def RelationshipType.instance(name)
      return @@names[name] if @@names.include?(name)
      @@names[name] = RelationshipType.new(name)
    end

    def to_s
      self.class.to_s + " name='#{@name}'"
    end

    def name
      @name
    end
    
    private
    
    def initialize(name)
      @name = name.to_s
      raise ArgumentError.new("Expect type of relation to be a name of at least one character") if @name.empty?
    end
    
  end
  
  class DepthStopEvaluator
    include StopEvaluator
    
    def initialize(depth)
      @depth = depth
    end
    
    def isStopNode(pos)
      pos.depth >= @depth
    end
  end
  #  /**
  #64	         * Traverses to depth 1.
  #65	         */
  #66	        public static final StopEvaluator DEPTH_ONE = new StopEvaluator()
  #67	        {
  #68	                public boolean isStopNode( TraversalPosition currentPosition )
  #69	                {
  #70	                        return currentPosition.depth() >= 1;
  #71	                }
  #72	        };
  
end