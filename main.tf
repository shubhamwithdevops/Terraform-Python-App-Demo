resource "aws_key_pair" "aws_key_pem" {
  key_name = "terraform-demo"
  public_key = file("/Users/joshinova/.ssh/id_rsa.pub")
}

resource "aws_vpc" "myvpc" {
  cidr_block = var.cidr
}

resource "aws_subnet" "public_subnet_terraform" {
  vpc_id = aws_vpc.myvpc.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "us-west-2a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id
}

resource "aws_route_table" "RT" {
  vpc_id = aws_vpc.myvpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }

}

resource "aws_route_table_association" "rta1" {
  subnet_id = aws_subnet.public_subnet_terraform.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_security_group" "webSG" {
  name = "webSG"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    description = "HTTP from VPC"
    from_port = 5000
    to_port = 5000
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    description = "SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port= 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    name = "Web-SG"
  }

}


resource "aws_instance" "server" {
  ami = "ami-04e08e36e17a21b56"
  instance_type = "t2.micro"
  key_name = aws_key_pair.aws_key_pem.key_name
  vpc_security_group_ids = [ aws_security_group.webSG.id ]
  subnet_id = aws_subnet.public_subnet_terraform.id


}

resource "null_resource" "configure_flask" {
  depends_on = [aws_instance.server]
  triggers = {
    app_hash = filesha1("${path.module}/app.py")  # re-runs when app.py changes
    rev      = "2"                                # bump to force re-run
  }
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("~/.ssh/id_rsa")
    host        = aws_instance.server.public_ip
  }
  provisioner "file" {
    source      = "app.py"
    destination = "/home/ec2-user/app.py"
  }
  provisioner "remote-exec" {
    inline = [
    "set -e",
    "if command -v dnf >/dev/null 2>&1; then PKG=dnf; else PKG=yum; fi",
    "sudo $PKG -y install python3 python3-pip",
    "[ -x /home/ec2-user/venv/bin/python ] || python3 -m venv /home/ec2-user/venv",
    "/home/ec2-user/venv/bin/pip install --upgrade pip flask",

    # create systemd service
    "sudo tee /etc/systemd/system/flask.service >/dev/null <<'EOL'\n[Unit]\nDescription=Flask App\nAfter=network.target\n\n[Service]\nUser=ec2-user\nWorkingDirectory=/home/ec2-user\nExecStart=/home/ec2-user/venv/bin/python /home/ec2-user/app.py\nRestart=always\n\n[Install]\nWantedBy=multi-user.target\nEOL",

    # reload, enable, and start service
    "sudo systemctl daemon-reload",
    "sudo systemctl enable --now flask",

     # Wait for service to start
    "sleep 5",

    # Retry up to 5 times for listening check
    "for i in {1..5}; do sudo ss -lntp | grep ':5000 ' && break || (echo 'Waiting for Flask...' && sleep 2); done"
  ]
  }
}
