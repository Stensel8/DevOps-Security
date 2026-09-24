<img src="saxion-logo.avif" alt="Saxion" height="80"> <img src="solidapps-logo.avif" alt="SolidApps" height="80">

# Casus SolidApps.

SolidApps is a company in Almere that focuses on managed web hosting. Managed web hosting means that the company hosts, monitors, manages, and optimizes web applications for customers to prevent downtime. This means that SolidApps is responsible for making a platform available to the customer on which the web application runs. The company has security as its spearhead. Especially in these times when we hear about security threats on a daily basis, SolidApps wants to unburden the customer in the field of security. For this, Solidapps must have a lot of knowledge and expertise, both of traditional forms of web hosting and new modern variants.

Many web applications still run directly on a web server that runs in a virtual machine, but more and more are being switched to Kubernetes. Web applications then run within Docker containers in a Kubernetes cluster.

Customers often program the web application themselves and are then responsible for the software. SolidApps also develops its own software to manage its own platform. Think of software for its own virtualization platform (based on open source Laragrid) or software for monitoring and securing the environment.
To develop this software, DevOps is used, the merging of Development and Operations. This is done by using CI/CD pipelines. Programming is done in multiple languages such as Javascript (by using Javascript frameworks) and C#. Visual Studio is used as the development environment. Web applications are sometimes hosted in the company's own data center, but increasingly in a public cloud such as Azure or AWS.

Security is central to this case. It is of utmost importance that the platform cannot be hacked. That would be fatal for the company. In particular, the security of Kubernetes clusters and the CI/CD pipelines requires attention because there are many new developments in this area and the design of security still has many questions.

SolidApps therefore wants to gain more experience in properly setting up security in a Kubernetes and DevOps environment. A Proof of Concept of a Kubernetes Cluster (consisting of a control node and a worker node) has been built combined with a CI/CD pipeline.

SolidApps has 2 commands:

1) In the test set-up, all kinds of security principles and products must be tested for operation and usability. The result must be recorded in a report.
2) Based on these results and on the basis of the literature, the aim is to arrive at a general design that will be applied to the entire infrastructure.  Design choices must be substantiated and advice must be given on the future design of the security for Kubernetes clusters and the CI/CD pipeline.
