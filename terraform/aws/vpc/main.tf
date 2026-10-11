data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

# Carve consecutive /24s out of the VPC CIDR, starting at subnet_index and
# spread round-robin across the available AZs. newbits is derived so each result
# is always a /24 regardless of the VPC prefix length (e.g. /16 -> newbits 8).
resource "aws_subnet" "this" {
  count                   = var.subnet_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.cidr_block, 24 - tonumber(split("/", var.cidr_block)[1]), var.subnet_index + count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "this" {
  count          = var.subnet_count
  subnet_id      = aws_subnet.this[count.index].id
  route_table_id = aws_route_table.public.id
}

# Keep existing single-subnet deployments in place instead of recreating them.
moved {
  from = aws_subnet.this
  to   = aws_subnet.this[0]
}

moved {
  from = aws_route_table_association.this
  to   = aws_route_table_association.this[0]
}
