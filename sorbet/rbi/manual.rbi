# typed: true

class Pathname
  sig do
    params(p1: T::Array[String], p2: Integer).returns(T::Array[Pathname])
  end
  def glob(p1, p2=0, &blk); end
end
