provider "aws" {
  region  = "ap-south-1"
  profile = "vikas"
  shared_credentials_file = "C:/Users/VIKAS/.aws/credentials"
}

variable "key_name" {
	default = "mykey1"	
}

resource "tls_private_key" "key1" {
  algorithm = "RSA"
}

resource "local_file" "save_key" {
    content  = tls_private_key.key1.private_key_pem
    filename = "mykey1.pem"
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = tls_private_key.key1.public_key_openssh
}



resource "aws_security_group" "mysg1" {
  name        = "my Security group1"
  description = "allow http and ssh"
  vpc_id      = "vpc-686b7700"

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mysg1"
  }
}



resource "aws_instance"  "myinstance1" {
  depends_on  = [ aws_security_group.mysg1 ]
  ami                    = "ami-0447a12f28fddb066"
  instance_type          = "t2.micro"
  key_name               = "mykey1"
  vpc_security_group_ids = [ aws_security_group.mysg1.id ]
  
  tags = {
    Name = "myinstance1"
  }
}


resource "aws_ebs_volume" "myebs1" {
  availability_zone = aws_instance.myinstance1.availability_zone
  size              = 1

  tags = {
    Name = "myebs1"
  }
}



resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.myebs1.id
  instance_id = aws_instance.myinstance1.id
  force_detach = true
}


  
resource "null_resource" "null1"  {
    depends_on    = [ aws_volume_attachment.ebs_att ]
  
    provisioner "local-exec" { command = "git clone https://github.com/VikasVerma25/terratest.git C:/Users/VIKAS/Desktop/terra/cloned" }
 
    connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.key1.private_key_pem
    host        = aws_instance.myinstance1.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/VikasVerma25/terratest.git /var/www/html/"
    ]
  }
  
}


resource "aws_s3_bucket" "image_bucket" {
  bucket = "vkv1484"
  acl    = "public-read"
}


resource "aws_s3_bucket_object" "bucket_object" {
  depends_on = [ aws_s3_bucket.image_bucket,
      		null_resource.null1		
	  	]
  key    = "cloudimage.png"
  bucket = aws_s3_bucket.image_bucket.id
  source = "C:/Users/VIKAS/Desktop/terra/cloned/cloudimage.png"
  acl    = "public-read"
  force_destroy = true
}


resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "This is origin access identity"
}

resource "aws_cloudfront_distribution" "distribution" {
    depends_on = [ aws_s3_bucket_object.bucket_object ]
    
    origin {
        domain_name = "vkv1484.s3.amazonaws.com"
        origin_id   = "S3-vkv1484" 

        s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }
       
    enabled         = true
    is_ipv6_enabled = true

    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-vkv1484"


        forwarded_values {
            query_string = false
        
            cookies {
               forward = "none"
            }
        }

        min_ttl     = 0
	default_ttl = 3600
        max_ttl     = 86400
 
        viewer_protocol_policy = "allow-all"
        
    }
    
    restrictions {
        geo_restriction {
            
            restriction_type = "none"
        }
    }


    
    viewer_certificate {
        cloudfront_default_certificate = true
    }
}




resource "null_resource" "null2" {
 depends_on = [ aws_cloudfront_distribution.distribution ]
 
 connection {
 type = "ssh"
 user = "ec2-user"
 private_key = tls_private_key.key1.private_key_pem
 host = aws_instance.myinstance1.public_ip
 }
 
 provisioner "remote-exec" {
 inline = [ 
    "echo -e \"\n<img src='http://${aws_cloudfront_distribution.distribution.domain_name}/${aws_s3_bucket_object.bucket_object.key}'>\" | sudo tee -a /var/www/html/index.html"
    ]
 }
}


output "myos_ip" {
  value = aws_instance.myinstance1.public_ip
}


resource "null_resource" "null3"  {

  depends_on = [ null_resource.null2 ]

	provisioner "local-exec" {
	    command = "start firefox  ${aws_instance.myinstance1.public_ip}"
  	}
}



