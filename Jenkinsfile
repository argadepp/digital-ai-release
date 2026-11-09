pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        TF_IN_AUTOMATION = 'true'
        TF_INPUT = 'false'
        TF_DIR = 'terraform'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Tooling') {
            steps {
                sh '''
                    set -eu
                    terraform version
                    terraform fmt -check -recursive
                '''
            }
        }

        stage('Terraform Init and Validate') {
            steps {
                dir("${TF_DIR}") {
                    sh '''
                        set -eu
                        terraform init -input=false
                        terraform validate
                    '''
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'azure-sp',
                        usernameVariable: 'ARM_CLIENT_ID',
                        passwordVariable: 'ARM_CLIENT_SECRET'
                    ),
                    string(credentialsId: 'azure-tenant-id', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'azure-subscription-id', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    dir("${TF_DIR}") {
                        sh '''
                            set -eu
                            terraform plan -input=false -out=tfplan
                            terraform show -no-color tfplan > tfplan.txt
                        '''
                        archiveArtifacts artifacts: 'tfplan.txt', fingerprint: true
                    }
                }
            }
        }

        stage('Approval') {
            steps {
                input(
                    message: 'Review the archived Terraform plan. Approve creation/update of the Azure Resource Group?',
                    ok: 'Approve Terraform Apply',
                    submitterParameter: 'APPROVED_BY'
                )
            }
        }

        stage('Terraform Apply') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'azure-sp',
                        usernameVariable: 'ARM_CLIENT_ID',
                        passwordVariable: 'ARM_CLIENT_SECRET'
                    ),
                    string(credentialsId: 'azure-tenant-id', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'azure-subscription-id', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    dir("${TF_DIR}") {
                        sh '''
                            set -eu
                            terraform apply -input=false -auto-approve tfplan
                            terraform output
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'Azure Resource Group Terraform deployment completed successfully.'
        }
        failure {
            echo 'Terraform pipeline failed. Review the Jenkins console output.'
        }
        always {
            echo 'Terraform pipeline execution finished.'
        }
    }
}
